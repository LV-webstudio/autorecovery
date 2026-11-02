# Procedimiento de emergencia: un equipo no responde

1. **Ping** a su IP (.33 PC, .37 portátil, .38 Mac, .50 Omen).
   - Responde pero la sesión de Claude no → relanzar su RETOMAR o reinicio remoto: `shutdown /r /t 60`.
2. **No responde** → `python3 scripts/despertar.py <equipo>` desde el Mac y esperar ~3 min.
   - ¿No sabes la MAC? → `scripts/buscar-mac-en-logs.sh <IP>`; o, con clave del router,
     `python3 -m shania_router.cli mac <IP>`.
3. **Desde fuera de casa** → por la pasarela cifrada: `python3 -m shania_router.remote wake <equipo>`
   (el agente del Mac emite el paquete en la LAN). Ver docs/ACCESO-REMOTO.md.
4. **Sigue sin responder** → corte de luz o cuelgue total → enchufe inteligente (apagar/encender);
   con la BIOS en "Power On", arranca solo.
5. **Nada funciona** → avisar a la persona responsable; decide si alguien debe ir al lugar.
6. **Anotar** el incidente en tu registro de red.
