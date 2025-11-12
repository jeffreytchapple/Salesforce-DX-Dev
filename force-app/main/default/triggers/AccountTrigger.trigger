trigger AccountTrigger on Account (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    // Always bulk-safe: operate on Trigger.new / Trigger.old (lists), not single records.
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            AccountTriggerHandler.beforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            AccountTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            AccountTriggerHandler.beforeDelete(Trigger.oldMap);
        }
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AccountTriggerHandler.afterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            AccountTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            AccountTriggerHandler.afterDelete(Trigger.oldMap);
        }
        if (Trigger.isUndelete) {
            AccountTriggerHandler.afterUndelete(Trigger.new);
        }
    }
}
