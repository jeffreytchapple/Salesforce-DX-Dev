public with sharing class AccountTriggerHandler {

    // BEFORE INSERT
    public static void beforeInsert(List<Account> newAccounts) {
        // Example: default a field
        for (Account acc : newAccounts) {
            if (acc.Industry == null) {
                acc.Industry = 'Not Specified';
            }
        }
    }

    // BEFORE UPDATE
    public static void beforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Example: prevent changing the Account Type if it's set to "Customer"
        for (Account acc : newAccounts) {
            Account oldAcc = oldMap.get(acc.Id);

            if (oldAcc.Type == 'Customer' && acc.Type != oldAcc.Type) {
                acc.Type.addError('You cannot change the Account Type for Customers.');
            }
        }
    }

    // BEFORE DELETE
    public static void beforeDelete(List<Account> oldAccounts) {
        // Example: prevent deletion if Account has Opportunities
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : oldAccounts) {
            accountIds.add(acc.Id);
        }

        Map<Id, Integer> oppCountByAccountId = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT AccountId, COUNT(Id) recordCount
            FROM Opportunity
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ]) {
            oppCountByAccountId.put((Id)ar.get('AccountId'), (Integer)ar.get('recordCount'));
        }

        for (Account acc : oldAccounts) {
            if (oppCountByAccountId.containsKey(acc.Id)) {
                acc.addError('You cannot delete an Account that has related Opportunities.');
            }
        }
    }

    // AFTER INSERT
    public static void afterInsert(List<Account> newAccounts) {
        // Example: create a related Task for each new Account
        List<Task> tasksToInsert = new List<Task>();

        for (Account acc : newAccounts) {
            tasksToInsert.add(new Task(
                WhatId     = acc.Id,
                Subject    = 'Follow up on new Account',
                Status     = 'Not Started',
                Priority   = 'Normal'
            ));
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // AFTER UPDATE
    public static void afterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Example: if Account’s Rating changes to 'Hot', create a Task
        List<Task> tasksToInsert = new List<Task>();

        for (Account acc : newAccounts) {
            Account oldAcc = oldMap.get(acc.Id);

            if (oldAcc.Rating != 'Hot' && acc.Rating == 'Hot') {
                tasksToInsert.add(new Task(
                    WhatId   = acc.Id,
                    Subject  = 'New HOT account – reach out',
                    Status   = 'Not Started',
                    Priority = 'High'
                ));
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // AFTER DELETE
    public static void afterDelete(List<Account> oldAccounts) {
        // Example: log deletions in a custom object (Account_Deletion_Log__c)
        // (Only if such an object exists; this is just illustrative)

        /*
        List<Account_Deletion_Log__c> logs = new List<Account_Deletion_Log__c>();

        for (Account acc : oldAccounts) {
            logs.add(new Account_Deletion_Log__c(
                Account_Name__c = acc.Name,
                Account_Id__c   = acc.Id
            ));
        }

        if (!logs.isEmpty()) {
            insert logs;
        }
        */
    }

    // AFTER UNDELETE
    public static void afterUndelete(List<Account> undeletedAccounts) {
        // Example: maybe recreate related Tasks or re-open associated records
        // Placeholder for future logic
    }
}
