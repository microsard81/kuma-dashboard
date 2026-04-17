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


def count_down_probes(bg: int, tim: int, iliad: int, nodeping: int, uptime: int) -> int:
    """
    Conta il numero di sonde con valore 0 (DOWN). Restituisce un intero 0-5.
    Ogni parametro: 0 = DOWN, 1 = UP.
    Proprietà metamorfica: count_down_probes(a,b,c,d,e) == 5 - (a+b+c+d+e).
    """
    return 5 - (bg + tim + iliad + nodeping + uptime)


def validate_threshold(value) -> bool:
    """
    Restituisce True se value è un intero (non booleano) in {1, 2, 3, 4, 5}.
    Esclude esplicitamente bool perché in Python bool è sottoclasse di int.
    """
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 5
