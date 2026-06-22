---
id: frontend
title: Frontend Flutter
sidebar_position: 5
---

# Frontend Flutter

O app mobile está em `mobile/financeview` e usa Flutter com Riverpod, GoRouter, Dio, Cognito, File Picker, Share Plus e notificações locais.

## Principais dependências

Arquivo: `mobile/financeview/pubspec.yaml`

- `flutter_riverpod`: gerenciamento de estado.
- `go_router`: navegação.
- `dio`: cliente HTTP.
- `amazon_cognito_identity_dart_2`: autenticação Cognito.
- `flutter_secure_storage`: armazenamento seguro de tokens.
- `file_picker`: seleção de PDF para importação.
- `fl_chart`: gráficos.
- `share_plus`: compartilhamento de relatórios.
- `flutter_local_notifications`: notificações locais.
- `shared_preferences`: deduplicação simples de notificações.

## Estrutura do app

```text
mobile/financeview/lib/
├── main.dart
├── core/
│   ├── config/app_config.dart
│   ├── network/api_client.dart
│   └── router/app_router.dart
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── transactions/
│   ├── import/
│   ├── analysis/
│   └── budgets/
└── shared/
    ├── services/
    ├── utils/
    └── widgets/
```

## Telas

| Tela | Caminho | Responsabilidade |
|---|---|---|
| Login | `features/auth/presentation/login_screen.dart` | Autenticação |
| Cadastro | `features/auth/presentation/signup_screen.dart` | Criar usuário |
| Confirmação | `features/auth/presentation/confirm_screen.dart` | Confirmar Cognito |
| Dashboard | `features/dashboard/presentation/dashboard_screen.dart` | Resumo financeiro |
| Receitas | `features/dashboard/presentation/income_transactions_screen.dart` | Listagem de entradas |
| Extratos | `features/transactions/presentation/transactions_screen.dart` | Gastos por categoria |
| Importação | `features/import/presentation/import_screen.dart` | Upload e revisão |
| Análise | `features/analysis/presentation/analysis_screen.dart` | IPCA e evolução mensal |
| Metas | `features/budgets/presentation/budgets_screen.dart` | Orçamentos mensais |

## Navegação

Arquivo: `mobile/financeview/lib/core/router/app_router.dart`

O app usa `GoRouter` com:

- redirecionamento para `/login` quando não autenticado;
- redirecionamento para `/dashboard` quando autenticado e acessando rota de auth;
- `ShellRoute` com `NavigationBar` para telas principais.

Rotas principais:

```text
/dashboard
/income
/transactions
/import
/analysis
/budgets
```

## Cliente HTTP

Arquivo: `mobile/financeview/lib/core/network/api_client.dart`

Responsabilidades:

- configurar `baseUrl`;
- aplicar `Authorization` com token Cognito;
- tratar `401`;
- converter erros Dio em mensagens amigáveis.

## Configuração

Arquivo: `mobile/financeview/lib/core/config/app_config.dart`

Contém configuração de Cognito e API. Em produção, recomenda-se substituir valores fixos por `--dart-define`, arquivo de configuração por ambiente ou pipeline de build. Esta documentação não expõe valores reais.

## Compartilhamento

Arquivo: `mobile/financeview/lib/shared/services/share_service.dart`

Permite compartilhar:

- resumo mensal no Dashboard;
- relatório de análise na tela Análise.

Em ambientes desktop onde o compartilhamento nativo pode falhar, o serviço usa fallback copiando o texto para a área de transferência.

## Notificações locais

Arquivo: `mobile/financeview/lib/shared/services/notification_service.dart`

Responsabilidades:

- inicializar `flutter_local_notifications`;
- solicitar permissões no Android/iOS;
- criar canal Android;
- emitir alertas de metas e orçamento;
- deduplicar alertas com `SharedPreferences`.

Permissão Android:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

## Tratamento de estados

O app usa `AsyncValue` do Riverpod e widgets como `AsyncErrorView` para lidar com:

- loading;
- erro;
- retry;
- ausência de dados.

## Observações de UX

- O preview de importação permite editar tipo e categoria antes de confirmar.
- O compartilhamento mostra `SnackBar` em ausência de dados ou fallback.
- Metas exibem feedback visual com barra de progresso.
