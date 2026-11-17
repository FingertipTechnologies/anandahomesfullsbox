public with sharing class DemandLineService {
    private static Map<String, List<List<Demand_Line__c>>> stagedLinesByDemandKey =
        new Map<String, List<List<Demand_Line__c>>>();

    public static void stageForInsert(
        Demands__c demand,
        List<Demand_Line__c> demandLines
    ) {
        if (demand == null) {
            throw new AuraHandledException('Demand is required to stage demand lines.');
        }
        String key = stagingKey(demand);
        if (!stagedLinesByDemandKey.containsKey(key)) {
            stagedLinesByDemandKey.put(key, new List<List<Demand_Line__c>>());
        }
        stagedLinesByDemandKey.get(key).add(
            demandLines == null ? new List<Demand_Line__c>() : demandLines
        );
    }

    public static void createForInsertedDemands(List<Demands__c> demands) {
        if (demands == null || demands.isEmpty()) return;

        List<Demand_Line__c> linesToInsert = new List<Demand_Line__c>();
        for (Demands__c demand : demands) {
            String key = stagingKey(demand);
            List<List<Demand_Line__c>> stagedGroups = stagedLinesByDemandKey.get(key);
            if (stagedGroups != null && !stagedGroups.isEmpty()) {
                List<Demand_Line__c> stagedLines = stagedGroups.remove(0);
                attachToDemand(demand.Id, stagedLines);
                linesToInsert.addAll(stagedLines);
                if (stagedGroups.isEmpty()) stagedLinesByDemandKey.remove(key);
            } else if (demand.Payment_Schedule__c != null) {
                Demand_Line__c fallbackLine = createFromSchedule(
                    new Payment_Schedule__c(Id = demand.Payment_Schedule__c),
                    demand.Demand_Component__c,
                    demand.Flat_Amount__c,
                    demand.GST_Amount__c,
                    demand.TDS_Amount__c,
                    demand.Interest_Amount__c
                );
                fallbackLine.Demand__c = demand.Id;
                linesToInsert.add(fallbackLine);
            }
        }
        insertLines(linesToInsert);
    }

    public static void clearStagedLines() {
        stagedLinesByDemandKey.clear();
    }

    public static Demand_Line__c createFromSchedule(
        Payment_Schedule__c schedule,
        String demandComponent,
        Decimal flatAmount,
        Decimal gstAmount,
        Decimal tdsAmount,
        Decimal interestAmount
    ) {
        Decimal flat = nz(flatAmount);
        Decimal gst = nz(gstAmount);
        Decimal tds = nz(tdsAmount);
        if (schedule == null || schedule.Id == null) {
            throw new AuraHandledException('A payment schedule is required for each demand line.');
        }

        return new Demand_Line__c(
            Payment_Schedule__c = schedule.Id,
            Demand_Component__c = demandComponent,
            Flat_Amount__c = flat,
            GST_Amount__c = gst,
            TDS_Amount__c = tds,
            Interest_Amount__c = nz(interestAmount),
            Demand_Amount__c = flat + gst + tds
        );
    }

    public static void insertForDemand(Id demandId, List<Demand_Line__c> demandLines) {
        attachToDemand(demandId, demandLines);
        insertLines(demandLines);
    }

    public static void attachToDemand(Id demandId, List<Demand_Line__c> demandLines) {
        if (demandId == null) {
            throw new AuraHandledException('Demand ID is required.');
        }
        if (demandLines == null || demandLines.isEmpty()) return;

        for (Demand_Line__c demandLine : demandLines) {
            demandLine.Demand__c = demandId;
        }
    }

    public static void insertLines(List<Demand_Line__c> demandLines) {
        if (demandLines == null || demandLines.isEmpty()) return;
        Set<Id> scheduleIds = new Set<Id>();
        for (Demand_Line__c demandLine : demandLines) {
            if (demandLine.Payment_Schedule__c != null) {
                scheduleIds.add(demandLine.Payment_Schedule__c);
            }
        }
        Map<Id, Payment_Schedule__c> schedulesById = new Map<Id, Payment_Schedule__c>();
        if (!scheduleIds.isEmpty()) {
            schedulesById = new Map<Id, Payment_Schedule__c>([
                SELECT Id, Name, Milestone_Name__c, Sequence__c, Percentage__c,
                       Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c, TDS_Amount_Paid__c
                FROM Payment_Schedule__c
                WHERE Id IN :scheduleIds
            ]);
        }
        for (Demand_Line__c demandLine : demandLines) {
            Payment_Schedule__c schedule = schedulesById.get(demandLine.Payment_Schedule__c);
            if (schedule == null) {
                throw new AuraHandledException(
                    'Could not load a payment schedule for a demand line.'
                );
            }
            demandLine.Milestone_Name__c = String.isNotBlank(schedule.Milestone_Name__c)
                ? schedule.Milestone_Name__c
                : schedule.Name;
            demandLine.Sequence__c = schedule.Sequence__c;
            demandLine.Percentage__c = schedule.Percentage__c;
            demandLine.Received_Flat_Amount__c = nz(schedule.Payment_Schedule_Amount_Paid__c);
            demandLine.Received_GST_Amount__c = nz(schedule.GST_Amount_Paid__c);
            demandLine.Received_TDS_Amount__c = nz(schedule.TDS_Amount_Paid__c);
            if (demandLine.Demand_Component__c == DemandComponentService.FLAT) {
                demandLine.Received_Amount__c =
                    demandLine.Received_Flat_Amount__c + demandLine.Received_TDS_Amount__c;
            } else if (demandLine.Demand_Component__c == DemandComponentService.GST) {
                demandLine.Received_Amount__c = demandLine.Received_GST_Amount__c;
            } else {
                demandLine.Received_Amount__c =
                    demandLine.Received_Flat_Amount__c
                    + demandLine.Received_GST_Amount__c
                    + demandLine.Received_TDS_Amount__c;
            }
        }
        insert demandLines;
    }

    public static void applyAmountOverrides(
        List<Demand_Line__c> demandLines,
        String demandComponent,
        Decimal flatAmount,
        Decimal gstAmount,
        Decimal tdsAmount
    ) {
        if (demandLines == null || demandLines.isEmpty()) return;

        if (demandComponent != DemandComponentService.GST) {
            allocateAmount(demandLines, 'Flat_Amount__c', nz(flatAmount));
            allocateAmount(demandLines, 'TDS_Amount__c', nz(tdsAmount));
        }
        if (demandComponent != DemandComponentService.FLAT) {
            allocateAmount(demandLines, 'GST_Amount__c', nz(gstAmount));
        }
        for (Demand_Line__c line : demandLines) {
            line.Demand_Amount__c = nz(line.Flat_Amount__c)
                + nz(line.GST_Amount__c)
                + nz(line.TDS_Amount__c);
        }
    }

    private static void allocateAmount(
        List<Demand_Line__c> demandLines,
        String fieldName,
        Decimal targetAmount
    ) {
        Decimal totalWeight = 0;
        for (Demand_Line__c line : demandLines) {
            totalWeight += nz((Decimal) line.get(fieldName));
        }

        Decimal allocated = 0;
        for (Integer i = 0; i < demandLines.size(); i++) {
            Decimal amount;
            if (i == demandLines.size() - 1) {
                amount = targetAmount - allocated;
            } else if (totalWeight > 0) {
                Decimal weight = nz((Decimal) demandLines[i].get(fieldName));
                amount = (targetAmount * weight / totalWeight)
                    .setScale(2, System.RoundingMode.HALF_UP);
                allocated += amount;
            } else {
                amount = i == 0 ? targetAmount : 0;
                if (i == 0) allocated += amount;
            }
            demandLines[i].put(fieldName, amount);
        }
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String stagingKey(Demands__c demand) {
        return String.valueOf(demand.Booking__c)
            + '|' + String.valueOf(demand.Payment_Schedule__c)
            + '|' + String.valueOf(demand.Demand_Component__c)
            + '|' + String.valueOf(demand.Demand_Type__c)
            + '|' + String.valueOf(demand.Demand_Amount__c)
            + '|' + String.valueOf(demand.Demand_Date__c)
            + '|' + String.valueOf(demand.Due_Date__c);
    }
}