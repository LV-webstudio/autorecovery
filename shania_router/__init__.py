"""shania_router · herramientas del router HGU de O2/Movistar para Shania Autorecovery."""
from .hgu import HGUClient, Device, parse_devices, mess_userpass

__all__ = ["HGUClient", "Device", "parse_devices", "mess_userpass"]
__version__ = "0.1.0"
