trigger MasterPaymentScheduleTrigger on Master_Payment_Schedule__c (after update) {
    if (Label.Enable_Master_Payment_Schedule_Trigger == 'true') {
        Set<Id> completedMasterIds = new Set<Id>();
        Map<Id, String> notificationBodies = new Map<Id, String>();
        Map<Id, Boolean> masterInterestMap = new Map<Id, Boolean>();

        for (Master_Payment_Schedule__c master : Trigger.new) {
            Master_Payment_Schedule__c oldMaster = Trigger.oldMap.get(master.Id);

            if (master.Status__c != oldMaster.Status__c && master.Status__c == 'Completed') {
                completedMasterIds.add(master.Id);
                notificationBodies.put(
                    master.Id,
                    'Milestone ' + master.Name + ' for ' + master.Project_Name__c +
                    ' is completed. You can now raise demands for the related booking(s).'
                );
            }

            if (master.Include_Interest__c != oldMaster.Include_Interest__c) {
                masterInterestMap.put(master.Id, master.Include_Interest__c);
            }
        }

        if (!completedMasterIds.isEmpty()) {
            List<Payment_Schedule__c> relatedSchedules = [
                SELECT Id, Payment_Due_Date__c, Master_Payment_Schedule__c,
                    Booking__r.OwnerId, Booking__r.CRM_Executive__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :completedMasterIds
            ];
            Map<Id, Set<String>> recipientsByMaster = new Map<Id, Set<String>>();
            Set<String> allRecipientIds = new Set<String>();

            for (Payment_Schedule__c schedule : relatedSchedules) {
                schedule.Payment_Due_Date__c = Trigger.newMap.get(
                    schedule.Master_Payment_Schedule__c
                ).Due_Date__c;
                schedule.Status__c = 'Completed';

                Set<String> recipientIds = recipientsByMaster.get(
                    schedule.Master_Payment_Schedule__c
                );
                if (recipientIds == null) {
                    recipientIds = new Set<String>();
                    recipientsByMaster.put(schedule.Master_Payment_Schedule__c, recipientIds);
                }

                Id bookingOwnerId = schedule.Booking__r.OwnerId;
                if (bookingOwnerId != null && String.valueOf(bookingOwnerId).startsWith('005')) {
                    recipientIds.add(String.valueOf(bookingOwnerId));
                    allRecipientIds.add(String.valueOf(bookingOwnerId));
                }

                Id crmExecutiveId = schedule.Booking__r.CRM_Executive__c;
                if (crmExecutiveId != null) {
                    recipientIds.add(String.valueOf(crmExecutiveId));
                    allRecipientIds.add(String.valueOf(crmExecutiveId));
                }
            }

            if (!relatedSchedules.isEmpty()) {
                update relatedSchedules;
            }

            Set<String> activeRecipientIds = new Set<String>();
            if (!allRecipientIds.isEmpty()) {
                for (User activeUser : [
                    SELECT Id
                    FROM User
                    WHERE Id IN :allRecipientIds AND IsActive = true
                ]) {
                    activeRecipientIds.add(String.valueOf(activeUser.Id));
                }
            }

            if (!activeRecipientIds.isEmpty()) {
                CustomNotificationType notificationType = [
                    SELECT Id
                    FROM CustomNotificationType
                    WHERE DeveloperName = 'Master_Payment_Schedule_Notification'
                    LIMIT 1
                ];

                for (Id masterId : recipientsByMaster.keySet()) {
                    Set<String> recipientIds = new Set<String>();
                    for (String recipientId : recipientsByMaster.get(masterId)) {
                        if (activeRecipientIds.contains(recipientId)) {
                            recipientIds.add(recipientId);
                        }
                    }
                    if (recipientIds.isEmpty()) {
                        continue;
                    }

                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationType.Id);
                    notification.setSenderId(UserInfo.getUserId());
                    notification.setTitle('Milestone Completed - Ready to Raise Demand');
                    notification.setBody(notificationBodies.get(masterId));
                    notification.setTargetId(masterId);
                    notification.send(recipientIds);
                }
            }
        }

        if (!masterInterestMap.isEmpty()) {
            List<Payment_Schedule__c> relatedSchedules = [
                SELECT Id, Include_Interest__c, Master_Payment_Schedule__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :masterInterestMap.keySet()
            ];

            for (Payment_Schedule__c schedule : relatedSchedules) {
                schedule.Include_Interest__c = masterInterestMap.get(
                    schedule.Master_Payment_Schedule__c
                );
            }

            if (!relatedSchedules.isEmpty()) {
                update relatedSchedules;
            }
        }
    }
}