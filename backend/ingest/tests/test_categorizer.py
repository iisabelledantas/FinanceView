import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from categorizer import (  # noqa: E402
    SAVINGS_CATEGORY,
    category_memory_signature,
    categorize_batch,
)


class LocalTransactionCategorizerTest(unittest.TestCase):
    def test_known_keywords_are_categorized(self):
        transactions = [
            self._transaction("IFOOD PEDIDO 123", -45.90, "DEBIT"),
            self._transaction("UBER TRIP", -21.00, "DEBIT"),
            self._transaction("SALARIO EMPRESA", 5000.00, "CREDIT"),
            self._transaction("FARMÁCIA SAO PAULO", -32.10, "DEBIT"),
            self._transaction("APLICACAO COFRINHOS", -100.00, "DEBIT"),
            self._transaction("LOJA SEM REGRA", -10.00, "DEBIT"),
        ]

        categorized = categorize_batch(transactions)

        self.assertEqual(categorized[0]["category"], "alimentacao")
        self.assertEqual(categorized[1]["category"], "transporte")
        self.assertEqual(categorized[2]["category"], "receita")
        self.assertEqual(categorized[3]["category"], "saude")
        self.assertEqual(categorized[4]["category"], SAVINGS_CATEGORY)
        self.assertEqual(categorized[5]["category"], "outros")

    def test_user_memory_has_priority_for_manual_changes(self):
        description = "MERCEARIA DO BAIRRO 123"
        memory = {category_memory_signature(description): "alimentacao"}

        categorized = categorize_batch(
            [self._transaction(description, -67.80, "DEBIT")],
            user_memory=memory,
        )

        self.assertEqual(categorized[0]["category"], "alimentacao")
        self.assertEqual(categorized[0]["categorySuggestionSource"], "user_memory")

    def test_savings_rule_overrides_user_memory(self):
        description = "APLICACAO COFRINHOS"
        memory = {category_memory_signature(description): "alimentacao"}

        categorized = categorize_batch(
            [self._transaction(description, -100.00, "DEBIT")],
            user_memory=memory,
        )

        self.assertEqual(categorized[0]["category"], SAVINGS_CATEGORY)
        self.assertEqual(categorized[0]["categorySuggestionSource"], "local_rules")

    def _transaction(self, description, raw_amount, credit_debit_type):
        return {
            "description": description,
            "rawAmount": raw_amount,
            "creditDebitType": credit_debit_type,
            "bookingDate": "2026-06-01",
        }


if __name__ == "__main__":
    unittest.main()
