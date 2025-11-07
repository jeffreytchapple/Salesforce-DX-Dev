public with sharing class ForecastController {
    @AuraEnabled(cacheable=true)
    public static ForecastService.ForecastSeries getMonthly(Integer historyMonths, Integer horizonMonths) {
        return ForecastService.getMonthlyForecast(historyMonths, horizonMonths);
    }

    @AuraEnabled
    public static void scoreOpportunities(List<Id> opportunityIds) {
        Map<Id, ForecastPredictor.PredictionResult> results = ForecastPredictor.score(opportunityIds);
        if (results.isEmpty()) return;
        List<Opportunity> updates = new List<Opportunity>();
        for (Id oid : results.keySet()) {
            ForecastPredictor.PredictionResult r = results.get(oid);
            Opportunity o = new Opportunity(Id=oid);
            o.PredictedProbability__c = r.predictedProbability;
            o.PredictedAmount__c = r.predictedAmount;
            updates.add(o);
        }
        if (!updates.isEmpty()) update updates;
    }
}
