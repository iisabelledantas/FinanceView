import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from health_score import calculate_health_score  # noqa: E402


class HealthScoreTest(unittest.TestCase):
    def test_income_expenses_and_savings_are_accounted_separately(self):
        health = calculate_health_score(
            [
                self._transaction(5000, "CREDIT", "receita"),
                self._transaction(-125.50, "DEBIT", "alimentacao"),
                self._transaction(-300, "DEBIT", "cofrinho_poupanca", "APLICACAO COFRINHOS"),
                self._transaction(100, "CREDIT", "cofrinho", "RESGATE COFRINHOS"),
                self._transaction(-200, "DEBIT", "financeiro", "APLICACAO COFRINHOS"),
                self._transaction(50, "CREDIT", "financeiro", "RESGATE COFRINHOS"),
            ],
            ipca_monthly=None,
        )

        self.assertEqual(health["total_income"], 5150.0)
        self.assertEqual(health["total_expenses"], 125.5)
        self.assertEqual(health["total_savings_balance"], 350.0)
        self.assertEqual(health["total_savings_movements"], 350.0)
        self.assertEqual(health["expenses_by_category"], {"alimentacao": 125.5})

    def _transaction(self, raw_amount, credit_debit_type, category, description=""):
        return {
            "rawAmount": raw_amount,
            "creditDebitType": credit_debit_type,
            "category": category,
            "description": description,
            "bookingDate": "2026-06-01",
        }


if __name__ == "__main__":
    unittest.main()
