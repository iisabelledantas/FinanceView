---
id: backend
title: Backend
sidebar_position: 6
---

# Backend

O backend é composto por Lambdas Python separadas por responsabilidade.

## Lambdas

### `backend/ingest`

Responsável por:

- gerar URL pré-assinada para upload;
- baixar PDF do S3;
- extrair texto/transações;
- acionar Textract quando necessário;
- normalizar transações;
- categorizar localmente;
- retornar preview;
- confirmar e salvar transações;
- publicar evento no SQS para recálculo de insights.

Arquivos principais:

- `backend/ingest/src/handler.py`
- `backend/ingest/src/categorizer.py`
- `backend/ingest/src/normalizer.py`
- `backend/ingest/src/parsers/pdf_parser.py`
- `backend/ingest/src/preprocessors/ocr.py`
- `backend/ingest/src/preprocessors/pdf_text.py`

### `backend/insights`

Responsável por:

- buscar transações por usuário/período;
- calcular receitas, despesas, poupança, cofrinho e evolução mensal;
- agrupar despesas por categoria;
- listar receitas;
- salvar metas;
- excluir transações;
- verificar metas e publicar alertas SNS.

Arquivos principais:

- `backend/insights/src/handler.py`
- `backend/insights/src/health_score.py`
- `backend/insights/src/budget_checker.py`

### `backend/market_data`

Responsável por:

- buscar indicadores do Banco Central;
- buscar cotações de câmbio na AwesomeAPI;
- gravar dados em cache no DynamoDB.

Arquivo principal:

- `backend/market_data/src/handler.py`

## Categorização local

Arquivo: `backend/ingest/src/categorizer.py`

A categorização não depende de API externa de IA. A abordagem atual usa:

- regras determinísticas;
- palavras-chave;
- normalização de acentos e caixa;
- tipo da transação;
- valor;
- memória por usuário.

Exemplos:

| Descrição | Categoria |
|---|---|
| `IFOOD PEDIDO` | `alimentacao` |
| `UBER TRIP` | `transporte` |
| `SALARIO EMPRESA` | `receita` |
| `FARMÁCIA` | `saude` |
| `APLICACAO COFRINHOS` | `cofrinho_poupanca` |
| desconhecida | `outros` |

## Memória de categorias

Quando o usuário altera manualmente uma categoria no preview e confirma a importação, o backend grava uma memória no DynamoDB usando chave:

```text
PK = USER#{user_id}
SK = CATEGORY_MEMORY#{signature}
```

Em imports futuros, essa memória tem prioridade, exceto para regras obrigatórias como cofrinho/poupança.

## Regra do cofrinho

O backend trata cofrinho tanto por categoria quanto por descrição, para cobrir dados antigos.

Regras:

- aplicação no cofrinho aumenta `total_savings_balance`;
- aplicação não entra em despesa comum;
- resgate do cofrinho reduz `total_savings_balance`;
- resgate entra como receita/entrada;
- despesas por categoria ignoram cofrinho;
- receitas podem listar resgates do cofrinho quando aplicável.

## Endpoints lógicos

Os endpoints são expostos pelo API Gateway:

| Método | Rota | Lambda | Finalidade |
|---|---|---|---|
| `POST` | `/upload-url` | ingest | Gerar URL pré-assinada |
| `POST` | `/statements` | ingest | Preview, confirmação ou processamento |
| `GET` | `/insights` | insights | Indicadores financeiros |
| `DELETE` | `/transactions` | insights | Excluir transação |
| `GET` | `/budgets` | insights | Listar metas |
| `POST` | `/budgets` | insights | Salvar meta |
| `GET` | `/market` | insights | Buscar mercado em cache |
