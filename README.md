# Case Técnico: Martech Specialist | Flutter Brazil

Pipeline que responde: **quais jogadores dormentes vale a pena reativar, com qual oferta, e quanto eles valem.**

## O problema

Duas coisas impediam a resposta: **Os valores estão em três moedas** e **A taxonomia de campanha está quebrada**.

## A resposta

Dos 250 jogadores, **119 são alvo acionável**: dormentes, com valor, liberados pelo compliance.

| | jogadores |
|---|---|
| base | 250 |
| − Dormentes | 164 |
| − Self Excluded | 14 |
| − KYC Status Non Verified | 53 |
| − Nunca depositaram ou Apostaram | 7 |
| **alvos dormentes acionáveis** | **119** |

> **[A PREENCHER]** — segmento recomendado, oferta, valor esperado.

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

Layout esperado em bronze: `bronze/{entidade}/ingest_date=YYYY-MM-DD/{entidade}.csv`.

## Arquitetura

![Arquitetura](docs/img/arquitetura.png)

| Lambda | Lê → escreve | Faz |
|---|---|---|
| `flutter-fx` | Frankfurter → `reference/` | ingere cotações do BCE, materializa tabela diária densa |
| `flutter-silver` | `bronze/` → `silver/` | valida, deduplica, quarentena, tipa, converte para BRL, parseia taxonomia |
| `flutter-gold` | `silver/` → `gold/` | monta o star schema |

Step Functions em sequência, EventBridge Scheduler mensal, métricas via EMF no CloudWatch.

**O câmbio é uma Lambda separada** porque API é problema de ingestão, não de transformação. **A tabela de câmbio é densa**, contendo uma linha por dia corrido, com carry-forward explícito, porque o BCE não publica em fim de semana.

## Modelo de dados

![Modelo gold](docs/img/modelo_gold.png)

Star schema Kimball: `dim_date`, `dim_player`, `dim_campaign` + `fact_deposit`, `fact_bet`, `fact_touchpoint`. Três fatos porque são três processos com grãos diferentes, `dim_date` é gerada e não derivada dos fatos, senão faltariam justamente os dias sem movimento.

O agregado por jogador vive em `vw_player_360`. Com 250 jogadores,
| View | Responde |
|---|---|
| `vw_player_360` | um jogador por linha: LTV, dormência, faixa de valor |
| `vw_segmentos_valor` | quantos jogadores e quanto valor em cada faixa |
| `vw_ltv_canal_oferta_produto` | LTV por canal × oferta × produto |
| `vw_conformidade_taxonomia` | aderência dos nomes ao padrão |
| `vw_dormencia_gaps` · `vw_dormencia_retorno` | evidência do limiar de 30 dias |

## Definições adotadas

Vivem em um lugar só — a `vw_player_360` — para ninguém recalcular com limiar diferente.

| Conceito | Definição | Por quê |
|---|---|---|
| **Atividade** | depósito confirmado **ou** aposta | apostar sem depositar é jogar com saldo: o jogador segue engajado |
| **Dormente** | > 30 dias sem atividade | é onde a taxa de retorno observada cai abaixo de 50% (65,5% até 30 dias → 48,9% de 31 a 45) |
| **Perdido** | > 84 dias | das 82 pausas que passaram desse ponto, **nenhuma** terminou em retorno — é reaquisição, não reativação |
| **Nunca ativou** | sem depósito e sem aposta | é problema de onboarding; misturar com dormência inflaria o alvo |
| **Valor (LTV)** | soma dos depósitos **confirmados** em BRL, pela taxa da data da transação | GGR não serve: é negativo neste dataset, os payouts foram sorteados sem margem da casa |
| **Faixa de valor** | quartis de LTV entre os acionáveis | faixa fixa em reais quebra quando muda período ou câmbio; o corte relativo se ajusta |
| **Acionável** | dormente **e** LTV > 0 **e** não bloqueado | 26 jogadores estão fora por compliance: 14 autoexcluídos, 12 com KYC rejeitado |
| **Canal** | o do event stream, não o declarado no nome da campanha | nomes iguais para coisas diferentes é como se produz relatório errado |
| **Oferta** | a do último toque antes da data de referência | 1.258 toques não sustentam modelo multi-touch |

O detalhamento da régua de dormência (distribuição de intervalos, curva de retorno) está em `vw_dormencia_retorno`.

## Imperfeições tratadas

| Onde | O quê | Tratamento |
|---|---|---|
| `deposits` | 25 linhas byte-idênticas | quarentena, mantém a primeira |
| `players` | 22 sem `acquisition_channel` (8,8%) | vira `unknown` — descartar tiraria 1/10 do LTV por canal |
| `campaigns` | `C007` sem nome, `C008` fora do padrão | 0/7 segmentos, marcadas não-conformes |
| `campaigns` | `C002`, `C012` com separador ou ordem trocada | recuperados: o parser casa por vocabulário, não por posição |
| `campaigns` | `C005` com erro de grafia | recuperado por fuzzy match; empate vira `unknown`, nunca palpite |
| `campaigns` | `C004` sem `product` e `audience` | 5/7 segmentos |
| `touchpoints` | 2 eventos posteriores à data de referência | quarentena — usar toque futuro é vazamento temporal |
| `bets` | 2.080 linhas com `payout = 0` | mantidas: aposta perdida, não dado faltante |

Nada sai em silêncio: toda linha removida vai para `quarantine/` com o motivo, e um check garante `linhas_bronze == silver + quarentena`.

## Decisões técnicas

- **Data Quality é contrato, não script.** Cada entidade declara schema, chave, domínio, formato e integridade referencial. `ERROR` derruba o pipeline; `WARN` registra e segue. Onde a imperfeição é conhecida, o check é `WARN` com folga — é isso que faz o alarme significar "algo mudou" em vez de "esse dataset é sujo".
- **Chave duplicada com conteúdo diferente nunca é deduplicada.** Não dá para saber qual linha é a verdadeira: é `ERROR` e para.
- **A gold publica de forma atômica.** Ou o star inteiro vai, ou nada vai.
- **`Retry` só em falha transitória de infra.** Repetir dado ruim gasta dinheiro para falhar igual.
- **Bronze é imutável para quem transforma.** As roles têm `Deny` explícito de escrita em `bronze/*`.

## Premissas

`preferred_currency` é atributo de perfil e não define a moeda da transação. Campanha arquivada continua explicando o passado — status não filtra a análise. Float64 com arredondamento a 2 casas basta para as magnitudes aqui (máx. ~2.000); com valores maiores, seria `decimal`.

## O que ficou de fora

**Ingestão de bronze** — os CSVs são carregados manualmente. 
**Histórico de snapshot** — a view recalcula a cada consulta. 
**Segmento de onboarding** — os 7 que nunca ativaram e os 28 sem depósito confirmado são público distinto, com oferta distinta.
