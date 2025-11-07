# Sales Cloud Forecasting App (Monthly, Segmented by Product Family)

This repo now includes a deployable forecasting solution:
- Data: Uses standard Opportunity and OpportunityLineItem with Product2.Family segmentation.
- Custom Fields:
  - Opportunity.PredictedAmount__c (Currency)
  - Opportunity.PredictedProbability__c (Percent)
- Config via Custom Metadata Type: Forecast_Config__mdt, with a Default record.
- Apex:
  - ForecastService.cls — Aggregates historical actuals, pipeline weighted, and predicted amounts monthly by Product Family.
  - ForecastPredictor.cls — Wraps Einstein Prediction Builder outputs when present and falls back to an Apex heuristic.
  - ForecastController.cls — Exposes AuraEnabled methods for LWC and writing predictions to Opportunity.
- LWC: forecastDashboard — Monthly line chart (Actual, Pipeline Weighted, Predicted) and a table.
- Permission Set: ForecastApp — Grants access to classes, fields, and CMDT.
- Manifest updated in manifest/package.xml.

Notes
- Monthly granularity as requested.
- Segmentation by Product Family (OpportunityLineItem.Product2.Family). If an Opportunity has no OLIs, values roll into "Unspecified".

Prereqs
- Salesforce CLI (sf) and Dev Hub enabled.
- If using Einstein Prediction Builder, ensure entitlements and setup in the target org.

Scratch org setup
1) Create a scratch org:
   sf org create scratch -f config/project-scratch-def.json -a ForecastApp -d 7

2) Deploy source:
   sf project deploy start -o ForecastApp

3) Assign permission set:
   sf org assign permset -o ForecastApp -n ForecastApp

4) Open the org:
   sf org open -o ForecastApp

5) Add the Forecast Dashboard to a Lightning App, Home, or Opportunity record page from the Lightning App Builder (component: "Forecast Dashboard").

Seeding sample data (optional)
- Create a few active Products with Family values and pricebook entries, then create Opportunities with OpportunityLineItems spanning past and future months to visualize trends. For quick testing you can run the included sample script (coming soon) or manually insert records.

Einstein Prediction Builder (optional)
- If you want to use Prediction Builder to provide PredictedProbability__c and/or PredictedAmount__c:
  - Build a prediction on Opportunity (e.g., "Will this Opportunity be won?" or "What is the predicted revenue?").
  - Map its score outputs to the custom fields:
    - PredictedProbability__c (0..1)
    - PredictedAmount__c (Currency)
  - When scores are present, ForecastPredictor.score will use them; otherwise it falls back to stage-weighted estimates and light trend smoothing.

Troubleshooting
- If the LWC shows "No data yet", ensure you have:
  - Active Products with Family populated
  - Opportunities with CloseDate across historical and forward months
  - OpportunityLineItems tied to those Products
- If you see deployment issues for metadata types:
  - Ensure API version 61.0 is available in your org.
  - Re-run: sf project deploy start -o ForecastApp
