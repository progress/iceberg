/*------------------------------------------------------------------------
    File        : health.i
    Syntax      :
    Description :
    Author(s)   : Peter Judge & Dustin Grau
    Created     : Fri Sept 6 013:24:09 EDT 2019
    Notes       :
  ----------------------------------------------------------------------*/

/* ***************************  Definitions  ************************** */

/*** PASOE HealthCheck ***/

define temp-table HealthConfig no-undo
    field probeid        as integer
    field parentid       as integer
    field composite      as logical
    field config_name    as character   serialize-name "name"
    field timestamp      as datetime-tz
    field calculation    as character
    field critical       as decimal     decimals 1
    field marginal       as decimal     decimals 1
    field description    as character
    field weight         as decimal     decimals 1
    field className      as character
    field enabled        as logical
    field failOnCritical as logical
    field config         as clob
    index pkProbe as primary probeid parentid config_name timestamp
    .

define temp-table HealthData no-undo
    field probeid        as integer
    field health         as decimal   decimals 1
    field marginal       as logical
    field critical       as logical
    field ignore         as logical
    field failOnCritical as logical
    field failedBy       as character
    field data_value     as clob      serialize-name "value"
    field lastpoll       as datetime-tz
    index pkProbe as primary probeid lastpoll
    .

define dataset HealthCheck for HealthConfig, HealthData.

define temp-table healthProbe no-undo
    field probeID   as integer
    field parentID  as integer
    field probeName as character
    index pukProbe as primary unique probeID parentID probeName
    .

define temp-table probeData no-undo
    field probeID    as integer
    field health     as decimal  decimals 1
    field isMarginal as logical
    field isCritical as logical
    field pollTime   as datetime
    index pkProbe as primary probeID
    .

define dataset healthTrend for healthProbe, probeData
    data-relation Probe for healthProbe, probeData relation-fields(probeID,probeID) nested.
