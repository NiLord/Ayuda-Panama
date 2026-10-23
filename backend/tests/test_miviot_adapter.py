import unittest
from unittest.mock import patch, MagicMock
from backend.src.adapters.miviot_adapter import MiviotAdapter, MiviotConsultaResult


HTML_ESCENARIO_A = """
<!DOCTYPE html>
<html>
<body>
  <div class="container mt-4">
    <div class="card border-success">
      <div class="card-body">
        <h5 class="card-title">Expediente de Afectación de Vivienda</h5>
        <p>Número de trámite: <strong>AFV/07877</strong></p>
        <p class="text-muted">Recibido el 12/10/2026</p>
        
        <div class="progress-steps d-flex">
          <div class="step">
            <span class="circle" style="background-color:#adb5bd">1</span>
            <span class="text-muted">Recepción y Registro</span>
          </div>
          <div class="step active">
            <span class="circle" style="background-color:#2e7d32; color:white">2</span>
            <span class="fw-bold">Evaluación Técnica en Sitio</span>
          </div>
          <div class="step">
            <span class="circle" style="background-color:#adb5bd">3</span>
            <span class="text-muted">Validación Social</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
"""

HTML_ESCENARIO_B = """
<!DOCTYPE html>
<html>
<body>
  <div class="container mt-4">
    <div class="alert alert-warning">
      No encontramos un reporte con esa cédula en nuestro sistema de afectaciones.
    </div>
  </div>
</body>
</html>
"""

HTML_ESCENARIO_C = """
<!DOCTYPE html>
<html>
<body>
  <div class="container mt-4">
    <div class="alert alert-danger">
      Formato de cédula no válido. Por favor verifique los guiones.
    </div>
  </div>
</body>
</html>
"""

HTML_PHASE1 = """
<!DOCTYPE html>
<html>
<body>
  <form action="/afectaciones/consulta" method="POST">
    <input type="hidden" name="csrf_token" value="abc123csrfTokenSecretXYZ" />
    <input type="text" name="cedula" />
    <button type="submit">Consultar</button>
  </form>
</body>
</html>
"""


class TestMiviotAdapter(unittest.TestCase):
    def test_extract_csrf_token(self):
        token = MiviotAdapter.extract_csrf_token(HTML_PHASE1)
        self.assertEqual(token, "abc123csrfTokenSecretXYZ")

    def test_parse_scenario_a_found(self):
        result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_A, "7-71-1473")
        self.assertTrue(result.encontrado)
        self.assertEqual(result.cedula, "7-71-1473")
        self.assertEqual(result.reporte, "AFV/07877")
        self.assertEqual(result.fecha_recibido, "12/10/2026")
        self.assertEqual(result.paso_actual, 2)
        self.assertEqual(result.estado_actual, "Vivienda evaluada. Pendiente asignación de programa.")
        self.assertIsNone(result.error)

    def test_parse_scenario_b_not_found(self):
        result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_B, "8-123-456")
        self.assertFalse(result.encontrado)
        self.assertEqual(result.cedula, "8-123-456")
        self.assertIsNone(result.reporte)
        self.assertIn("No encontramos", result.mensaje)

    def test_parse_scenario_c_invalid_format(self):
        result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_C, "invalid-id")
        self.assertFalse(result.encontrado)
        self.assertEqual(result.error, "FORMATO_INVALIDO")

    @patch("urllib.request.build_opener")
    def test_full_two_phase_flow_success(self, mock_build_opener):
        # Mocking Phase 1 (GET) and Phase 2 (POST) responses
        mock_opener = MagicMock()
        mock_build_opener.return_value = mock_opener

        resp_phase1 = MagicMock()
        resp_phase1.read.return_value = HTML_PHASE1.encode("utf-8")
        resp_phase1.__enter__.return_value = resp_phase1

        resp_phase2 = MagicMock()
        resp_phase2.read.return_value = HTML_ESCENARIO_A.encode("utf-8")
        resp_phase2.__enter__.return_value = resp_phase2

        mock_opener.open.side_effect = [resp_phase1, resp_phase2]

        adapter = MiviotAdapter()
        result = adapter.consultar_cedula("7-71-1473")

        self.assertTrue(result.encontrado)
        self.assertEqual(result.reporte, "AFV/07877")
        self.assertEqual(result.paso_actual, 2)
        self.assertEqual(result.estado_actual, "Vivienda evaluada. Pendiente asignación de programa.")
