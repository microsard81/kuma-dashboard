# severity.py


def compute_severity(bg: int, tim: int, iliad: int, nodeping: int) -> int:
    """
    Calcola la severità di un monitor.
    0 = verde (tutti UP), 1 = giallo (mismatch), 2 = rosso (tutti DOWN).
    Ogni parametro: 0 = DOWN, 1 = UP.
    """
    if bg == 1 and tim == 1 and iliad == 1 and nodeping == 1:
        return 0
    all_states = {bg, tim, iliad, nodeping}
    if len(all_states) > 1:
        return 1
    return 2


def compute_global_state(severities: list) -> str:
    """
    Calcola lo stato globale a partire dalla lista di severità.
    """
    if any(s == 2 for s in severities):
        return "RED"
    if any(s == 1 for s in severities):
        return "YELLOW"
    return "GREEN"
