trigger EventTrigger on Event(before update, before delete, after update) {
  Map<Id, Event> oldEvents = (Map<Id, Event>) Trigger.oldMap;
  if (Trigger.isBefore && Trigger.isUpdate) {
    EventTriggerHandler.beforeUpdate(Trigger.new, oldEvents);
  } else if (Trigger.isBefore && Trigger.isDelete) {
    EventTriggerHandler.beforeDelete(oldEvents);
  } else if (Trigger.isAfter && Trigger.isUpdate) {
    EventTriggerHandler.afterUpdate(Trigger.new, oldEvents);
  }
}
