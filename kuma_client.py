# kuma_client.py

import re
import logging

import requests
from requests.exceptions import Timeout, ConnectionError, HTTPError
from typing import Dict
from config import HTTP_TIMEOUT

logger = logging.getLogger(__name__)

def normalize(name: str) -> str:
    """Normalizza i nomi per confronto."""
    return re.sub(r"\s+", " ", name.strip())

def load_monitors(host: str, slug: str) -> Dict[str, str]:
    """
    Ritorna { monitor_name_normalized : monitor_display_name_original }
    """
    url = f"https://{host}/api/status-page/{slug}"
    try:
        r = requests.get(url, timeout=HTTP_TIMEOUT)
        r.raise_for_status()
        data = r.json()

        results = {}

        for group in data.get("publicGroupList", []):
            for m in group.get("monitorList", []):
                name_norm = normalize(m["name"])
                results[name_norm] = m["name"]
        return results
    except Timeout:
        logger.error("Timeout contattando %s", url)
        return {}
    except ConnectionError:
        logger.error("Errore di connessione verso %s", url)
        return {}
    except HTTPError as e:
        logger.error("Errore HTTP %s da %s", e.response.status_code, url)
        return {}