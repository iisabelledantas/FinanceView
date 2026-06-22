---
id: overview
title: Visão Geral
sidebar_position: 2
---

# Visão Geral

## Objetivo

O FinanceView tem como objetivo ajudar usuários a entenderem sua saúde financeira mensal a partir de extratos bancários. A aplicação centraliza transações, classifica gastos, calcula indicadores, exibe metas de orçamento e facilita a análise periódica.

## Problema resolvido

Extratos bancários costumam ser difíceis de analisar manualmente. O usuário precisa identificar receitas, despesas, transferências, gastos recorrentes e movimentações internas, como cofrinho/poupança. O FinanceView automatiza esse fluxo com:

- importação de PDF;
- categorização automática local;
- revisão manual antes da confirmação;
- cálculo de receitas, despesas, poupança e gastos por categoria;
- metas de orçamento;
- alertas e compartilhamento de resumo financeiro.

## Funcionalidades principais

- Cadastro, confirmação e login com Amazon Cognito.
- Navegação mobile com telas de início, extratos, importação, análise, metas e receitas.
- Upload de extrato PDF para S3 usando URL pré-assinada.
- Extração de transações de PDFs textuais e fallback para OCR assíncrono com Textract.
- Preview de transações antes da persistência.
- Categorização local baseada em regras, palavras-chave, tipo/valor da transação e memória do usuário.
- Aprendizado simples a partir de categorias alteradas manualmente.
- Tratamento especial para cofrinho/poupança.
- Dashboard com receitas, despesas, taxa de poupança, cofrinho e gastos por categoria.
- Tela de receitas e tela de despesas por categoria.
- Metas de orçamento com alertas.
- Notificações locais no app Flutter.
- Compartilhamento de resumo mensal e relatório de análise.
- Consumo de API externa para indicadores de mercado.


