public with sharing class ForecastPredictor {
    public class PredictionResult {
        @AuraEnabled public Decimal predictedProbability; // 0..1
        @AuraEnabled public Decimal predictedAmount;      // currency
        public PredictionResult(Decimal p, Decimal a) { predictedProbability = p; predictedAmount = a; }
    }

    /**
     * Score a list of Opportunity Ids:
     * - If Einstein Prediction Builder scores exist on the record (PredictedProbability__c / PredictedAmount__c), use them.
     * - Otherwise compute a heuristic probability and predicted amount.
     */
    public static Map<Id, PredictionResult> score(List<Id> opportunityIds) {
        Map<Id, PredictionResult> out = new Map<Id, PredictionResult>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return out;

        // Pull Opportunities with basic fields and stage for heuristic
        List<Opportunity> opps = [
            SELECT Id, Amount, StageName, Probability, CloseDate, ForecastCategoryName,
                   PredictedProbability__c, PredictedAmount__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        // Build simple stage weight defaults if no probability present
        Map<String, Decimal> stageWeights = defaultStageWeights();

        for (Opportunity o : opps) {
            Decimal prob = (o.PredictedProbability__c != null) ? o.PredictedProbability__c :
                           (o.Probability != null ? (o.Probability / 100) : stageWeights.get(o.StageName));
            if (prob == null) prob = 0;
            Decimal amt = (o.Amount == null ? 0 : o.Amount);
            Decimal pAmt = (o.PredictedAmount__c != null) ? o.PredictedAmount__c : (amt * prob);

            // Optional smoothing toward historical trend based on the last 3 months closed-won for the same stage
            Decimal trendAdj = lastMonthsTrendAdjustment(3);
            pAmt = Math.max(0, pAmt * trendAdj);

            out.put(o.Id, new PredictionResult(prob, pAmt));
        }
        return out;
    }

    // Returns a light seasonality/trend factor ~ [0.9..1.1] using recent closed-won seasonality
    private static Decimal lastMonthsTrendAdjustment(Integer months) {
        Date today = Date.today();
        Date start = Date.newInstance(today.year(), today.month(), 1).addMonths(-months);
        // Compute avg of monthly closed-won amounts over the window using two-step aggregation
        List<AggregateResult> monthly = [
            SELECT CALENDAR_YEAR(CloseDate) y, CALENDAR_MONTH(CloseDate) m, SUM(Amount) amt
            FROM Opportunity
            WHERE IsWon = true AND CloseDate >= :start AND CloseDate <= :today
            GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_MONTH(CloseDate)
        ];
        if (monthly.isEmpty()) return 1;
        Decimal sum = 0;
        for (AggregateResult ar : monthly) {
            sum += (Decimal) ar.get('amt');
        }
        Decimal avg = sum / monthly.size();
        if (avg == null || avg == 0) return 1;
        // Baseline factor 1.0 (placeholder for future scaling); keep clamp to avoid extremes
        Decimal factor = 1;
        if (factor < 0.9) factor = 0.9;
        if (factor > 1.1) factor = 1.1;
        return factor;
    }

    private static Map<String, Decimal> defaultStageWeights() {
        Map<String, Decimal> m = new Map<String, Decimal>();
        // Common defaults; admins can adjust via real Probability on stages
        m.put('Prospecting', 0.1);
        m.put('Qualification', 0.2);
        m.put('Needs Analysis', 0.3);
        m.put('Value Proposition', 0.4);
        m.put('Id. Decision Makers', 0.5);
        m.put('Perception Analysis', 0.6);
        m.put('Proposal/Price Quote', 0.65);
        m.put('Negotiation/Review', 0.75);
        m.put('Closed Won', 1);
        m.put('Closed Lost', 0);
        return m;
    }
}
