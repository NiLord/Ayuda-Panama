"""
MIVIOT Afectaciones de Vivienda Client & Parser
Interacciona con el controlador web de Odoo de MIVIOT (https://www.miviot.gob.pa/afectaciones/consulta).
Ejecuta el handshake CSRF + cookies de sesión en 2 fases y analiza la respuesta HTML.
"""

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import http.cookiejar
import json
import logging
import re
import urllib.parse
import urllib.request
from typing import Dict, Any, Optional, Tuple

from ..utils.cedula_normalizer import normalize_cedula

logger = logging.getLogger(__name__)

MIVIOT_URL = "https://www.miviot.gob.pa/afectaciones/consulta"
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


@dataclass
class MiviotConsultaResult:
    encontrado: bool
    cedula: str
    reporte: Optional[str] = None
    fecha_recibido: Optional[str] = None
    paso_actual: Optional[int] = None
    estado_actual: Optional[str] = None
    mensaje: Optional[str] = None
    error: Optional[str] = None
    timestamp_consulta: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class MiviotAdapter:
    """Adaptador para el servicio web de consulta de afectaciones del MIVIOT."""

    def __init__(self, timeout_seconds: int = 10, user_agent: str = DEFAULT_USER_AGENT):
        self.timeout_seconds = timeout_seconds
        self.user_agent = user_agent

    def consultar_cedula(self, cedula_raw: str) -> MiviotConsultaResult:
        """
        Ejecuta el flujo completo de 2 fases conservando la misma sesión/cookie.
        """
        cedula_norm = normalize_cedula(cedula_raw)
        if not cedula_norm:
            return MiviotConsultaResult(
                encontrado=False,
                cedula=cedula_raw or "",
                error="FORMATO_INVALIDO",
                mensaje="El formato de cédula ingresado no es válido para Panamá (ej. 7-71-1473).",
                timestamp_consulta=datetime.now(timezone.utc).isoformat(),
            )

        cookie_jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

        try:
            # Fase 1: GET Handshake y extracción de csrf_token
            get_req = urllib.request.Request(
                MIVIOT_URL,
                headers={"User-Agent": self.user_agent}
            )
            with opener.open(get_req, timeout=self.timeout_seconds) as resp:
                html_phase1 = resp.read().decode("utf-8", errors="replace")

            csrf_token = self.extract_csrf_token(html_phase1)
            if not csrf_token:
                logger.error("No se pudo extraer el csrf_token de la Fase 1 en MIVIOT.")
                return MiviotConsultaResult(
                    encontrado=False,
                    cedula=cedula_norm,
                    error="CSRF_ERROR",
                    mensaje="No fue posible establecer conexión segura con el portal de MIVIOT.",
                    timestamp_consulta=datetime.now(timezone.utc).isoformat(),
                )

            # Fase 2: POST con sesión y cédula
            post_data = urllib.parse.urlencode({
                "csrf_token": csrf_token,
                "cedula": cedula_norm,
            }).encode("utf-8")

            post_req = urllib.request.Request(
                MIVIOT_URL,
                data=post_data,
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Referer": MIVIOT_URL,
                    "User-Agent": self.user_agent,
                }
            )

            with opener.open(post_req, timeout=self.timeout_seconds) as resp:
                html_phase2 = resp.read().decode("utf-8", errors="replace")

            return self.parse_response_html(html_phase2, cedula_norm)

        except Exception as e:
            logger.exception("Error al conectar con el servidor de MIVIOT: %s", str(e))
            return MiviotConsultaResult(
                encontrado=False,
                cedula=cedula_norm,
                error="CONEXION_ERROR",
                mensaje=f"Fallo en la comunicación con el portal de MIVIOT: {str(e)}",
                timestamp_consulta=datetime.now(timezone.utc).isoformat(),
            )

    @staticmethod
    def extract_csrf_token(html: str) -> Optional[str]:
        """Extrae el token CSRF del HTML de Odoo."""
        match = re.search(r'<input[^>]+name=["\']csrf_token["\'][^>]+value=["\']([^"\']+)["\']', html, re.IGNORECASE)
        if not match:
            # Probar orden inverso de atributos value y name
            match = re.search(r'<input[^>]+value=["\']([^"\']+)["\'][^>]+name=["\']csrf_token["\']', html, re.IGNORECASE)
        return match.group(1) if match else None

    @classmethod
    def parse_response_html(cls, html: str, cedula: str) -> MiviotConsultaResult:
        """
        Evalúa el HTML de respuesta según los tres escenarios técnicos especificados:
        - Escenario A: Consulta Exitosa (.border-success)
        - Escenario B: Cédula sin registros (.alert-warning)
        - Escenario C: Formato inválido (.alert-danger)
        """
        now_iso = datetime.now(timezone.utc).isoformat()

        # Escenario B: Cédula sin registros
        if "alert-warning" in html or "No encontramos un reporte con esa cédula" in html:
            return MiviotConsultaResult(
                encontrado=False,
                cedula=cedula,
                mensaje="No encontramos un reporte con esa cédula en el MIVIOT.",
                timestamp_consulta=now_iso,
            )

        # Escenario C: Formato no válido
        if "alert-danger" in html or "Formato de cédula no válido" in html:
            return MiviotConsultaResult(
                encontrado=False,
                cedula=cedula,
                error="FORMATO_INVALIDO",
                mensaje="El formato de cédula no es reconocido por el sistema del MIVIOT.",
                timestamp_consulta=now_iso,
            )

        # Escenario A: Consulta Exitosa (Reporte encontrado)
        # Buscar tarjeta border-success o contenedor de reporte AFV
        if "border-success" in html or "AFV/" in html:
            # 1. Extraer número de reporte (ej. AFV/07877)
            reporte_match = re.search(r'<strong>\s*(AFV/[0-9A-Za-z]+)\s*</strong>', html)
            if not reporte_match:
                reporte_match = re.search(r'(AFV/[0-9A-Za-z]+)', html)
            reporte_id = reporte_match.group(1) if reporte_match else None

            # 2. Extraer fecha de recepción (ej. Recibido el 12/10/2026)
            fecha_match = re.search(r'Recibido\s+el\s+([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})', html, re.IGNORECASE)
            fecha_recibido = fecha_match.group(1) if fecha_match else None

            # 3. Detectar fase activa (1 a 5) y estado descriptivo
            # El paso activo tiene un círculo con background-color:#2e7d32 y texto con clase .fw-bold
            paso_actual, estado_actual = cls._extract_etapa_activa(html)

            return MiviotConsultaResult(
                encontrado=True,
                cedula=cedula,
                reporte=reporte_id,
                fecha_recibido=fecha_recibido,
                paso_actual=paso_actual,
                estado_actual=estado_actual or "En Proceso",
                mensaje="Reporte y trámite activo localizado en MIVIOT",
                timestamp_consulta=now_iso,
            )

        # Si no coincidió con ninguna estructura esperada
        return MiviotConsultaResult(
            encontrado=False,
            cedula=cedula,
            error="RESPUESTA_DESCONOCIDA",
            mensaje="La respuesta recibida del portal MIVIOT no pudo ser interpretada.",
            timestamp_consulta=now_iso,
        )

    @staticmethod
    def _extract_etapa_activa(html: str) -> Tuple[Optional[int], Optional[str]]:
        """
        Extrae el paso actual (1 al 5) y la descripción de la etapa activa.
        Busca elementos con color verde (#2e7d32) o clase fw-bold en el bloque de fases.
        """
        paso_actual = None
        estado_actual = None

        # Lista estándar de las 5 etapas oficiales del MIVIOT:
        etapas_miviot = [
            "Recepción y Registro de Solicitud",
            "Evaluación Técnica en Sitio",
            "Validación Socioeconómica y Social",
            "Asignación de Beneficio / Solución Habitacional",
            "Entrega de Ayuda o Vivienda Finalizada"
        ]

        # Buscar el paso numérico asociado al color verde #2e7d32
        # Ej: <div ... style="...background-color:#2e7d32...">2</div>
        paso_match = re.search(r'background-color\s*:\s*#2e7d32[^>]*>\s*([1-5])\s*<', html, re.IGNORECASE)
        if paso_match:
            try:
                paso_actual = int(paso_match.group(1))
            except ValueError:
                pass

        # Buscar texto descriptivo con clase fw-bold
        # Ej: <span class="fw-bold">Evaluación Técnica en Sitio</span> o <p class="... fw-bold ...">...</p>
        bold_match = re.search(r'<[^>]+class=["\'][^"\']*fw-bold[^"\']*["\'][^>]*>\s*([^<]+)\s*<', html)
        if bold_match:
            estado_actual = bold_match.group(1).strip()

        # Si encontramos el paso numérico pero no el texto, inferir por índice de lista
        if paso_actual and not estado_actual and 1 <= paso_actual <= len(etapas_miviot):
            estado_actual = etapas_miviot[paso_actual - 1]

        # Si encontramos el texto pero no el paso, inferir el paso por el texto
        if estado_actual and not paso_actual:
            for idx, etapa in enumerate(etapas_miviot, start=1):
                if etapa.lower() in estado_actual.lower() or estado_actual.lower() in etapa.lower():
                    paso_actual = idx
                    break

        return paso_actual or 1, estado_actual or "En Evaluación"
