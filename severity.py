# severity.py


def compute_severity(bg: int, tim: int, iliad: int, nodeping: int, uptime: int) -> int:
    """
    Calcola la severità di un monitor.
    0 = verde (tutti UP), 1 = giallo (mismatch), 2 = rosso (tutti DOWN).
    Ogni parametro: 0 = DOWN, 1 = UP.
    Cinque sonde: bg, tim, iliad, nodeping, uptime.
    """
    all_states = {bg, tim, iliad, nodeping, uptime}
    if all_states == {1}:
        return 0
    if all_states == {0}:
        return 2
    return 1


def compute_global_state(severities: list) -> str:
    """
    Calcola lo stato globale a partire dalla lista di severità.
    """
    if any(s == 2 for s in severities):
        return "RED"
    if any(s == 1 for s in severities):
        return "YELLOW"
    return "GREEN"
