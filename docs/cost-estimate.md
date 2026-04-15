# Stima costi Azure - Intune.Up

Prezzi indicativi West Europe, Pay-As-You-Go. Aprile 2026.

## Senza Application Gateway (setup attuale)

| Risorsa | SKU | Costo stimato/mese |
|---------|-----|-------------------|
| Azure Function HTTP | B1 Basic | ~€11 |
| Azure Function SB | B1 Basic | ~€11 |
| Storage Account x2 | Standard LRS | ~€2 |
| Service Bus | Standard | ~€8 |
| Log Analytics | Per-GB (5GB free/mese) | ~€0-10 (dipende dal volume) |
| Key Vault | Standard | ~€0.03/10K ops |
| App Configuration | Free | €0 |
| Automation Account | Basic (500 min free) | ~€0 |
| VNet + Private Endpoints | 6 endpoints | ~€42 (€7/endpoint/mese) |
| Private DNS Zones | 6 zone | ~€3 |
| **Totale** | | **~€77-87/mese** |

## Con Application Gateway + WAF v2

| Risorsa | SKU | Costo stimato/mese |
|---------|-----|-------------------|
| Tutto quanto sopra | | ~€77-87 |
| App Gateway WAF_v2 | 1 istanza, fisso | ~€246 |
| App Gateway capacity units | Variabile (traffico) | ~€5-15 |
| Public IP Standard | | ~€3 |
| **Totale** | | **~€331-351/mese** |

## Delta

| | Senza App GW | Con App GW + WAF |
|---|---|---|
| Costo mensile | ~€82 | ~€340 |
| Delta | - | **+€258/mese** |
| WAF (OWASP 3.2) | No | Si |
| DDoS L7 | No | Si |
| Bot protection | No | Si |
| SSL offloading | No | Si |
| Costo annuale | ~€984 | ~€4.080 |

## Note

- I costi delle Function App B1 possono essere ridotti condividendo un singolo App Service Plan
  (una sola istanza B1 per entrambe le Functions = ~€11 invece di ~€22)
- I Private Endpoints sono il costo piu significativo nella versione base (~€42/mese)
- L'App Gateway WAF_v2 ha un costo fisso rilevante (~€246/mese) indipendente dal traffico
- Per ambienti dev/test si puo omettere l'App Gateway e usare solo mTLS nativo
- Per produzione enterprise il WAF e raccomandato
- I volumi di Log Analytics dipendono dal numero di device e dalla frequenza di raccolta
  (stima: 100K device x 1KB/giorno x 30gg = ~3GB/mese, rientra nel free tier)
