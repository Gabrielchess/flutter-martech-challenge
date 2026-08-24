# Case Técnico: Martech Specialist | Flutter Brazil

Pipeline que responde: **quais jogadores dormentes vale a pena reativar, com qual oferta, e quanto eles valem.**

## Definições adotadas

| Conceito | Definição | Por quê |
|---|---|---|
| **Atividade** | depósito confirmado **ou** aposta | Jogador segue engajado |
| **Dormente** | > 30 dias sem atividade | Taxa de retorno cai abaixo de 50% |
| **Nunca ativou** | sem depósito e sem aposta | Problema de onboarding |

## A resposta

Dos 250 jogadores, **119 são alvo acionável**: dormentes, com valor, liberados pelo compliance.

### Filtros aplicados:
− Dormentes: 164

− Self Excluded: 14

− KYC Status Non Verified: 53

− Nunca depositaram ou Apostaram: 7

**Alvos dormentes acionáveis: 119**

> **[A PREENCHER]** — segmento recomendado, oferta, valor esperado.

## Arquitetura

| Lambda | Lê → escreve | Faz |
| Recurso | Configuração |
|---|---|
| **S3** | Bucket único |
| **Lambda** × 3 | Python 3.14 |
| **IAM** | Uma role por Lambda |
| **Step Functions** | Standard |
| **EventBridge Scheduler** | Mensal, dia 1 às 03:00 UTC |
| **Glue Data Catalog** | Database `flutter_martech` |
| **Athena** | Output location fixo |
| **CloudWatch** | Log groups |

**O câmbio é uma Lambda separada** porque API é problema de ingestão, não de transformação. **A tabela de câmbio é densa**, contendo uma linha por dia corrido, com carry-forward explícito, porque o BCE não publica em fim de semana.

| Lambda | Lê → escreve | Faz |
|---|---|---|
| `flutter-fx` | Frankfurter → `reference/` | ingere cotações do BCE, materializa tabela diária densa |
| `flutter-silver` | `bronze/` → `silver/` | valida, deduplica, quarentena, tipa, converte para BRL, parseia taxonomia |
| `flutter-gold` | `silver/` → `gold/` | monta o star schema |

## Modelo de dados

Star schema Kimball: `dim_date`, `dim_player`, `dim_campaign` + `fact_deposit`, `fact_bet`, `fact_touchpoint`. Três fatos porque são três processos com grãos diferentes, `dim_date` é gerada e não derivada dos fatos, senão faltariam justamente os dias sem movimento.

| Tabela | Tipo | Grão | Medidas |
|---|---|---|---|
| `dim_date` | dimensão | um dia corrido | — |
| `dim_player` | dimensão | um jogador | — |
| `dim_campaign` | dimensão | uma campanha | — |
| `fact_deposit` | transacional | uma tentativa de depósito | `amount`, `amount_brl` |
| `fact_bet` | transacional | uma aposta | `stake_brl`, `payout_brl`, `net_brl` |


O agregado por jogador vive em `vw_player_360`. Com 250 jogadores,
| View | Responde |
|---|---|
| `vw_player_360` | um jogador por linha: LTV, dormência, faixa de valor |
| `vw_segmentos_valor` | quantos jogadores e quanto valor em cada faixa |
| `vw_ltv_canal_oferta_produto` | LTV por canal × oferta × produto |
| `vw_conformidade_taxonomia` | aderência dos nomes ao padrão |
| `vw_dormencia_gaps` · `vw_dormencia_retorno` | evidência do limiar de 30 dias |

## Data Quality

| Onde | O quê | Tratamento |
|---|---|---|
| `deposits` | 25 linhas byte-idênticas | quarentena, mantém a primeira |
| `players` | 22 sem `acquisition_channel` (8,8%) | vira `unknown` — descartar tiraria 1/10 do LTV por canal |
| `campaigns` | `C007` sem nome, `C008` fora do padrão | marcadas não-conformes |
| `campaigns` | `C002`, `C012` com separador ou ordem trocada | recuperados: o parser casa por vocabulário, não por posição |
| `campaigns` | `C005` com erro de grafia | recuperado por fuzzy match; empate vira `unknown`, nunca palpite |
| `campaigns` | `C004` sem `product` e `audience` | 5/7 segmentos |
| `touchpoints` | 2 eventos posteriores à data de referência | quarentena — usar toque futuro é vazamento temporal |
| `bets` | 2.080 linhas com `payout = 0` | mantidas: aposta perdida, não dado faltante |

## Como rodar

```bash
./scripts/build_lambdas.sh                       # empacota src/ em dist/

cd terraform
cp terraform.tfvars.example terraform.tfvars     # confira o pandas_layer_arn da região
terraform init && terraform apply

aws s3 cp ../data/raw/ s3://flutter-martech-lakehouse/bronze/ --recursive --include "*.csv"
terraform output -raw comando_disparar_pipeline | bash

cd .. && python sql/run_athena.py sql/athena_gold.sql sql/athena_silver.sql
```
