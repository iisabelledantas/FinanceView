import 'package:flutter/material.dart';

const categoryLabels = {
  'alimentacao': 'Alimentação',
  'transporte': 'Transporte',
  'moradia': 'Moradia',
  'saude': 'Saúde',
  'educacao': 'Educação',
  'lazer': 'Lazer',
  'vestuario': 'Vestuário',
  'financeiro': 'Financeiro',
  'receita': 'Receita',
  'salario': 'Salário',
  'cofrinho_poupanca': 'Cofrinho/Poupança',
  'outros': 'Outros',
};

String formatCategory(String category) {
  return categoryLabels[category] ??
      category
          .split('_')
          .map((part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
}

IconData categoryIcon(String category) => switch (category) {
      'alimentacao' => Icons.restaurant,
      'transporte' => Icons.directions_car,
      'moradia' => Icons.home,
      'saude' => Icons.local_hospital,
      'educacao' => Icons.school,
      'lazer' => Icons.sports_esports,
      'vestuario' => Icons.checkroom,
      'financeiro' => Icons.account_balance,
      'receita' => Icons.payments,
      'salario' => Icons.payments,
      'cofrinho_poupanca' => Icons.savings,
      _ => Icons.category,
    };
