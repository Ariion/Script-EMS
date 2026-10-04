Config = {}

Config.Locale = 'fr'           -- 'fr' | 'en'
Config.Webhook = ''            -- webhook Discord (optionnel)

Config.Framework = 'auto'      -- 'qbcore' | 'esx' | 'standalone'
Config.Phone     = 'auto'      -- 'lb-phone' | 'qb-phone' | 'npwd' | 'standalone'
-- ENTREPRISES : tout se configure ici, sans toucher au code.
Config.Businesses = {
  ['omc'] = {
    label = 'Ocean Medical Center', type = 'hospital',
    color = '#0aa4c4', job = 'ambulance',
    services = {
      { id = 'consult', name = 'Consultation',  duration = 15, price = 150 },
      { id = 'checkup', name = 'Bilan complet', duration = 30, price = 400 },
    }
  },
  ['garage_ls'] = {
    label = 'LS Customs', type = 'mechanic',
    color = '#c8842a', job = 'mechanic',
    services = {
      { id = 'vidange',    name = 'Vidange',    duration = 20, price = 250 },
      { id = 'reparation', name = 'Reparation', duration = 45, price = 800 },
    }
  },
}

Config.OpenHour        = 8
Config.CloseHour       = 22
Config.ReminderMinutes = 10  -- rappel envoyé X minutes avant le RDV
