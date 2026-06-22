---
id: database
title: Banco de Dados
sidebar_position: 8
---

# Banco de Dados

O projeto usa DynamoDB em duas tabelas principais:

- tabela de transações;
- tabela de cache de mercado.

## Tabela de transações

Criada em `infra/modules/storage/main.tf`.

Chaves:

```text
PK: string
SK: string
```

Padrões de itens:

### Transações

```text
PK = USER#{user_id}
SK = TXN#{bookingDate}#{transactionId}
```

Campos comuns:

- `transactionId`;
- `externalId`;
- `bookingDate`;
- `description`;
- `category`;
- `creditDebitType`;
- `transactionType`;
- `status`;
- `amount`;
- `rawAmount`;
- `currency`.

### Metas

```text
PK = USER#{user_id}
SK = BUDGET#{category}
```

Campos comuns:

- `category`;
- `monthly_limit`;
- `current_spent`;
- `usage_pct`;
- `created_at`;
- `updated_at`.

### Memória de categorização

```text
PK = USER#{user_id}
SK = CATEGORY_MEMORY#{signature}
```

Campos comuns:

- `signature`;
- `category`;
- `description_sample`;
- `updated_at`;
- `usage_count`.

## Tabela de cache de mercado

Criada em `infra/modules/storage/main.tf`.

Chave:

```text
PK: string
```

Itens esperados:

- `IPCA`;
- `SELIC`;
- `EXCHANGE_RATES`.

Campos:

- `value`;
- `updated_at`;
- `expires_at`.

O campo `expires_at` é usado como TTL para expirar dados de mercado.

## Consultas principais

### Buscar transações do período

```text
PK = USER#{user_id}
SK begins_with TXN#{YYYY-MM}
```

### Buscar metas

```text
PK = USER#{user_id}
SK begins_with BUDGET#
```

### Buscar memória de categorias

```text
PK = USER#{user_id}
SK begins_with CATEGORY_MEMORY#
```

## Cuidados com tipos

O boto3 exige `Decimal` para números no DynamoDB. Por isso o backend converte valores numéricos antes de gravar.

