---
id: repository-structure
title: Estrutura de Pastas
sidebar_position: 4
---

# Estrutura de Pastas

```text
financeview/
├── backend/
│   ├── ingest/
│   │   ├── src/
│   │   │   ├── handler.py
│   │   │   ├── categorizer.py
│   │   │   ├── normalizer.py
│   │   │   ├── parsers/
│   │   │   └── preprocessors/
│   │   └── tests/
│   ├── insights/
│   │   ├── src/
│   │   │   ├── handler.py
│   │   │   ├── health_score.py
│   │   │   └── budget_checker.py
│   │   └── tests/
│   └── market_data/
│       └── src/
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── api_gateway/
│       ├── auth/
│       ├── lambdas/
│       ├── messaging/
│       └── storage/
├── mobile/
│   └── financeview/
│       ├── lib/
│       │   ├── core/
│       │   ├── features/
│       │   └── shared/
│       ├── android/
│       ├── ios/
│       ├── linux/
│       ├── web/
│       └── test/
├── docs/
└── sidebars.js
```

## Pastas principais

### `backend/ingest`

Responsável por upload, leitura de PDF, OCR, normalização, categorização e persistência de transações.

### `backend/insights`

Responsável por buscar transações, calcular indicadores, listar receitas/despesas, salvar metas e disparar alertas.

### `backend/market_data`

Responsável por consultar APIs externas e gravar indicadores no cache DynamoDB.

### `infra`

Infraestrutura como código com Terraform. Define recursos AWS e permissões IAM.

### `mobile/financeview`

Aplicativo Flutter. Contém telas, serviços, cliente HTTP, autenticação e navegação.

### `docs`

Documentação técnica em Markdown compatível com Docusaurus.

