# FinanceView

FinanceView é uma aplicação mobile de finanças pessoais com backend serverless na AWS. O projeto permite importar extratos em PDF, revisar transações, categorizar gastos localmente, acompanhar receitas/despesas, gerenciar metas e consultar análises financeiras.

Video: https://drive.google.com/file/d/1mZbEX1dxxDS-aerZM5itsiyToOQkgiZc/view?usp=sharing

## Principais funcionalidades

- App mobile em Flutter com autenticação, dashboard, extratos, importação, análise e metas.
- Importação de extratos bancários em PDF.
- Categorização local de transações por regras e histórico.
- Compartilhamento de resumo financeiro e notificações locais.
- Backend Python em AWS Lambda com API Gateway.
- Persistência em DynamoDB e infraestrutura provisionada com Terraform.
- Documentação técnica em Docusaurus.

## Estrutura

```text
backend/              Lambdas Python de ingestão, insights e dados de mercado
infra/                Infraestrutura Terraform
mobile/financeview/   Aplicação Flutter
docs/                 Documentação Docusaurus
```

## Como executar

### App Flutter

```bash
cd mobile/financeview
flutter pub get
flutter run
```

### Documentação

```bash
cd docs
npm install
npm run start
```

### Build da documentação

```bash
cd docs
npm run build
```

### Testes

```bash
cd mobile/financeview
flutter test
```

```bash
python -m pytest backend/ingest/tests backend/insights/tests
```

## Infraestrutura

A infraestrutura fica em `infra/` e utiliza Terraform para provisionar recursos AWS como API Gateway, Lambdas, Cognito, DynamoDB e mensageria.

```bash
cd infra
terraform init
terraform plan
terraform apply
```

Arquivos sensíveis como `.env`, credenciais AWS e `terraform.tfvars` não devem ser versionados.

## Documentação completa

A documentação detalhada está em `docs/docs/` e cobre arquitetura, frontend, backend, banco de dados, infraestrutura e serviços utilizados.

Para visualizar:

```bash
cd docs
npm run start
```

