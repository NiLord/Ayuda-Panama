import pytest
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


def test_extract_csrf_token():
    token = MiviotAdapter.extract_csrf_token(HTML_PHASE1)
    assert token == "abc123csrfTokenSecretXYZ"


def test_parse_scenario_a_found():
    result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_A, "7-71-1473")
    assert result.encontrado is True
    assert result.cedula == "7-71-1473"
    assert result.reporte == "AFV/07877"
    assert result.fecha_recibido == "12/10/2026"
    assert result.paso_actual == 2
    assert result.estado_actual == "Evaluación Técnica en Sitio"
    assert result.error is None


def test_parse_scenario_b_not_found():
    result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_B, "8-123-456")
    assert result.encontrado is False
    assert result.cedula == "8-123-456"
    assert result.reporte is None
    assert "No encontramos" in result.mensaje


def test_parse_scenario_c_invalid_format():
    result = MiviotAdapter.parse_response_html(HTML_ESCENARIO_C, "invalid-id")
    assert result.encontrado is False
    assert result.error == "FORMATO_INVALIDO"


@patch("urllib.request.build_opener")
def test_full_two_phase_flow_success(mock_build_opener):
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

    assert result.encontrado is True
    assert result.reporte == "AFV/07877"
    assert result.paso_actual == 2
    assert result.estado_actual == "Evaluación Técnica en Sitio"
