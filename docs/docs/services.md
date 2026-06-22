---
id: services
title: Serviços Utilizados
sidebar_position: 9
---

# Serviços Utilizados

## AWS

| Serviço | Uso |
|---|---|
| Cognito | Cadastro, login e emissão de JWT |
| API Gateway | API REST protegida por Cognito |
| Lambda | Backend serverless |
| DynamoDB | Transações, metas, memória e cache |
| S3 | Armazenamento de PDFs importados |
| Textract | OCR de PDFs sem texto embutido |
| SQS | Evento de importação concluída para recálculo |
| SNS | Alertas de orçamento no backend |
| EventBridge Scheduler | Atualização periódica de dados de mercado |
| CloudWatch Logs | Logs de execução |

## APIs externas

### Banco Central do Brasil

Usado pela Lambda `market_data` para buscar:

- SELIC;
- IPCA.

Arquivo:

```text
backend/market_data/src/handler.py
```

### AwesomeAPI

Usada para cotações de moedas, como USD/BRL e EUR/BRL.

## Serviços mobile

| Dependência | Uso |
|---|---|
| `file_picker` | Selecionar PDF |
| `share_plus` | Compartilhar resumo/relatório |
| `flutter_local_notifications` | Alertas locais |
| `flutter_secure_storage` | Tokens e dados de sessão |
| `shared_preferences` | Deduplicação de notificações |

## Observações

- APIs externas podem falhar; a Lambda `market_data` trata falhas com logs e segue atualizando os indicadores disponíveis.
- O app consome dados de mercado por meio do backend, não diretamente das APIs externas.
- O OCR via Textract depende de região AWS suportada.
