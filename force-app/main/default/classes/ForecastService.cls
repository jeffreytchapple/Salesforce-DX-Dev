public with sharing class ForecastService {
    public class MonthBucket {
        @AuraEnabled public Date monthStart;
        @AuraEnabled public Decimal actualAmount;
        @AuraEnabled public Decimal pipelineWeighted;
        @AuraEnabled public Decimal predictedAmount;
        @AuraEnabled public String productFamily;
        public MonthBucket(Date m, String family) {
            monthStart = m; productFamily = family;
            actualAmount = 0; pipelineWeighted = 0; predictedAmount = 0;
        }
    }
    public class ForecastSeries {
        @AuraEnabled public List<MonthBucket> buckets;
        @AuraEnabled public Date minMonth;
        @AuraEnabled public Date maxMonth;
        public ForecastSeries(List<MonthBucket> b) {
            buckets = b;
            if (!b.isEmpty()) {
                minMonth = b[0].monthStart;
                maxMonth = b[b.size()-1].monthStart;
            }
        }
    }

    public static List<MonthBucket> getMonthlyBuckets(Date startMonth, Integer horizonMonths, Set<String> families) {
        List<MonthBucket> buckets = new List<MonthBucket>();
        for (Integer i = 0; i < horizonMonths; i++) {
            Date m = startMonth.addMonths(i);
            for (String fam : families) {
                buckets.add(new MonthBucket(m, fam));
            }
        }
        return buckets;
    }

    public static Date startOfMonth(Date d) {
        return Date.newInstance(d.year(), d.month(), 1);
    }

    public static Set<String> getProductFamilies() {
        // Query distinct families from Products with active = true as a reasonable segment source
        Set<String> fams = new Set<String>();
        for (AggregateResult ar : [
            SELECT Family fam FROM Product2 WHERE IsActive = true AND Family != null GROUP BY Family
        ]) {
            fams.add((String) ar.get('fam'));
        }
        if (fams.isEmpty()) fams.add('Unspecified');
        return fams;
    }

    /**
     * Returns monthly actuals and pipeline rollups for the window [historyMonths back .. horizonMonths forward],
     * segmented by Product2.Family (via OpportunityLineItem).
     * - actuals: closed won in the month (CloseDate in month, IsWon = true)
     * - pipelineWeighted: sum(Amount * stage weight) for open opps in month
     * - predictedAmount: from Opportunity.PredictedAmount__c when available, else heuristic
     */
    @AuraEnabled(cacheable=true)
    public static ForecastSeries getMonthlyForecast(Integer historyMonths, Integer horizonMonths) {
        if (historyMonths == null) historyMonths = 12;
        if (horizonMonths == null) horizonMonths = 6;

        Date today = Date.today();
        Date start = startOfMonth(today).addMonths(-historyMonths);
        Integer totalMonths = historyMonths + horizonMonths + 1; // include current month

        Set<String> families = getProductFamilies();
        List<MonthBucket> buckets = getMonthlyBuckets(start, totalMonths, families);

        // Index buckets by (month,family)
        Map<String, MonthBucket> keyToBucket = new Map<String, MonthBucket>();
        for (MonthBucket b : buckets) {
            keyToBucket.put(key(b.monthStart, b.productFamily), b);
        }

        // Historical actuals: Closed Won by CloseDate month, split by line items family
        // Actuals via OLIs rolled up per Opp month/family
        List<AggregateResult> arOpps = [
            SELECT CALENDAR_YEAR(CloseDate) y, CALENDAR_MONTH(CloseDate) m, Id
            FROM Opportunity
            WHERE IsWon = true
              AND CloseDate >= :start
              AND CloseDate <= :start.addMonths(totalMonths-1).addDays(27)
            GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate), Id
        ];
        Set<Id> wonOppIds = new Set<Id>();
        Map<Id, Date> oppToMonth = new Map<Id, Date>();
        for (AggregateResult ar : arOpps) {
            Integer y = (Integer) ar.get('y');
            Integer m = (Integer) ar.get('m');
            Date monthStart = Date.newInstance(y, m, 1);
            Id oppId = (Id) ar.get('Id');
            wonOppIds.add(oppId);
            oppToMonth.put(oppId, monthStart);
        }
        if (!wonOppIds.isEmpty()) {
            for (AggregateResult ar2 : [
                SELECT OpportunityId oid, Product2.Family fam, SUM(TotalPrice) amt
                FROM OpportunityLineItem
                WHERE OpportunityId IN :wonOppIds
                GROUP BY OpportunityId, Product2.Family
            ]) {
                Id oid = (Id) ar2.get('oid');
                String fam = (String) ar2.get('fam');
                if (fam == null) fam = 'Unspecified';
                Date monthStart = oppToMonth.get(oid);
                if (monthStart != null) {
                    MonthBucket b = keyToBucket.get(key(monthStart, fam));
                    if (b != null) {
                        b.actualAmount += (Decimal) ar2.get('amt');
                    }
                }
            }
        }

        // Pipeline: open opps by expected close month, weighted by stage prob or PredictedProbability__c when present
        // Also collect predicted amounts if set.
        List<Opportunity> pipes = [
            SELECT Id, Amount, StageName, Probability, CloseDate, PredictedAmount__c, PredictedProbability__c
            FROM Opportunity
            WHERE IsClosed = false
              AND CloseDate >= :start
              AND CloseDate <= :start.addMonths(totalMonths-1).addDays(27)
        ];
        Map<Id, List<OpportunityLineItem>> oliByOpp = new Map<Id, List<OpportunityLineItem>>();
        if (!pipes.isEmpty()) {
            for (OpportunityLineItem oli : [
                SELECT Id, OpportunityId, Quantity, UnitPrice, Product2.Family
                FROM OpportunityLineItem
                WHERE OpportunityId IN :pipes
            ]) {
                List<OpportunityLineItem> l = oliByOpp.get(oli.OpportunityId);
                if (l == null) { l = new List<OpportunityLineItem>(); oliByOpp.put(oli.OpportunityId, l); }
                l.add(oli);
            }
        }

        for (Opportunity o : pipes) {
            Date mStart = startOfMonth(o.CloseDate);
            Decimal stageProb = (o.PredictedProbability__c != null) ? o.PredictedProbability__c : (o.Probability != null ? (o.Probability / 100) : 0);
            Decimal oppAmt = (o.Amount == null ? 0 : o.Amount);
            Decimal predictedAmt = (o.PredictedAmount__c == null ? 0 : o.PredictedAmount__c);

            List<OpportunityLineItem> lis = oliByOpp.get(o.Id);
            if (lis == null || lis.isEmpty()) {
                // No line items; attribute to Unspecified family
                MonthBucket b = keyToBucket.get(key(mStart, 'Unspecified'));
                if (b != null) {
                    b.pipelineWeighted += oppAmt * stageProb;
                    b.predictedAmount += (predictedAmt > 0 ? predictedAmt : oppAmt * stageProb);
                }
            } else {
                for (OpportunityLineItem li : lis) {
                    String fam = li.Product2 != null ? li.Product2.Family : null;
                    if (fam == null) fam = 'Unspecified';
                    Decimal liAmt = (li.Quantity == null ? 0 : li.Quantity) * (li.UnitPrice == null ? 0 : li.UnitPrice);
                    MonthBucket b = keyToBucket.get(key(mStart, fam));
                    if (b != null) {
                        b.pipelineWeighted += liAmt * stageProb;
                        // Distribute predicted amount proportionally to line items by amount; if no predicted set, use weighted
                        Decimal basis = oppAmt != 0 ? (liAmt / oppAmt) : 0;
                        Decimal liPred = (predictedAmt > 0 ? predictedAmt * basis : liAmt * stageProb);
                        b.predictedAmount += liPred;
                    }
                }
            }
        }

        // Return series
        // Sort buckets by month then family for deterministic order
        buckets.sort(new ComparatorMonthFamily());
        return new ForecastSeries(buckets);
    }

    public class ComparatorMonthFamily implements System.Comparator<MonthBucket> {
        public Integer compare(MonthBucket a, MonthBucket b) {
            if (a.monthStart == b.monthStart) {
                return a.productFamily.compareTo(b.productFamily);
            }
            return a.monthStart.daysBetween(b.monthStart);
        }
    }

    private static String key(Date m, String fam) { return String.valueOf(m.year()) + '-' + String.valueOf(m.month()) + '|' + fam; }
}
