// ============================================================
// Data Collection Rule (DCR) – per use case
// Creates a custom Log Analytics table and a DCR that routes data
// from the Logs Ingestion API into that table.
//
// Table naming convention : {tablePrefix}_{useCase}_CL
// Stream naming convention: Custom-{tablePrefix}_{useCase}_CL
//
// The schema covers the fixed top-level fields written by ProcessorFunction.
// Use-case-specific payload fields are stored in the 'Data' dynamic column
// so one DCR template works for all use cases without schema changes.
//
// Add additional DCR instances in main.bicep for each use case you need,
// then store each DCR's immutableId under:
//   IntuneUp:LogAnalytics:Dcr:{UseCase}:ImmutableId
// in App Configuration (via config-seed.bicep).
// ============================================================

param name string
param location string
param dceResourceId string
param workspaceResourceId string
param tablePrefix string = 'IntuneUp'
param useCase string      // e.g. 'LoginInformation' → table IntuneUp_LoginInformation_CL
param retentionDays int = 90
param tags object = {}

var tableName = '${tablePrefix}_${useCase}_CL'
var streamName = 'Custom-${tableName}'

// ---- Custom Log Analytics table ----
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(workspaceResourceId, '/'))
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: [
        { name: 'TimeGenerated', type: 'dateTime' }
        { name: 'DeviceId',      type: 'string'   }
        { name: 'DeviceName',    type: 'string'   }
        { name: 'UPN',           type: 'string'   }
        { name: 'UseCase',       type: 'string'   }
        { name: 'ReceivedAt',    type: 'dateTime' }
        { name: 'FunctionRegion',type: 'string'   }
        { name: 'Data',          type: 'dynamic'  }
      ]
    }
    retentionInDays: retentionDays
    plan: 'Analytics'
  }
}

// ---- Data Collection Rule ----
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: name
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dceResourceId
    streamDeclarations: {
      '${streamName}': {
        columns: [
          { name: 'DeviceId',       type: 'string'   }
          { name: 'DeviceName',     type: 'string'   }
          { name: 'UPN',            type: 'string'   }
          { name: 'UseCase',        type: 'string'   }
          { name: 'ReceivedAt',     type: 'datetime' }
          { name: 'FunctionRegion', type: 'string'   }
          { name: 'Data',           type: 'dynamic'  }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ streamName ]
        destinations: [ 'la-destination' ]
        outputStream: streamName
        transformKql: 'source | extend TimeGenerated = todatetime(ReceivedAt)'
      }
    ]
  }
  dependsOn: [ customTable ]
}

output dcrImmutableId string = dcr.properties.immutableId
output dcrResourceId string = dcr.id
output tableName string = tableName
output streamName string = streamName
