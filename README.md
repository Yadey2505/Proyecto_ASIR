# Infraestructura de almacenamiento y servicios para centro educativo

Este proyecto documenta el diseño e implementación de una infraestructura de red y almacenamiento orientada a un entorno educativo, con separación clara de roles entre profesorado y alumnado, acceso remoto seguro y administración centralizada.

---

## 🎯 Objetivo del proyecto

El objetivo principal es proporcionar un sistema que permita:

- Al **profesorado** disponer de un espacio privado y persistente para almacenar y gestionar archivos.
- Al **alumnado** acceder a recursos comunes sin necesidad de autenticación.
- Al **administrador** gestionar usuarios, permisos y accesos de forma segura y automatizada.
- Permitir **acceso remoto** a los servicios sin exponerlos directamente a Internet.

---

## 🏗️ Arquitectura general

La infraestructura se apoya en las siguientes tecnologías:

- **Hipervisor:** Proxmox VE
- **Servidor de archivos:** srv-files (Linux)
- **Almacenamiento:** NAS montado mediante NFS
- **Compartición de archivos:** Samba
- **Acceso remoto:** ZeroTier
- **Despliegue y clonación de equipos:** FOG Project

La arquitectura está diseñada para minimizar la superficie de ataque y facilitar el mantenimiento a largo plazo.

---

## 🌐 Redes utilizadas

- **Red LAN:** `192.168.1.0/24`
- **Red secundaria:** `192.168.192.0/24`
- **Red virtual privada:** ZeroTier (`10.x.x.x`)

El acceso remoto se realiza exclusivamente a través de ZeroTier.

---

## 📂 Estructura del repositorio
docs/
scripts/
diagrams/

- **docs/** → Documentación técnica detallada  
- **scripts/** → Scripts de automatización  
- **diagrams/** → Diagramas de red y arquitectura  

---

## 📁 Estructura del almacenamiento

El NAS se monta en el servidor de archivos y se organiza de la siguiente forma:
/mnt/nas
├── profesorado/
│ ├── usuario1/
│ └── usuario2/
└── alumnado/


### Profesorado
- Carpeta privada por usuario
- Acceso autenticado mediante Samba
- Permisos de lectura y escritura

### Alumnado
- Carpeta común
- Acceso como invitado (guest)
- Sin usuarios locales ni Samba
- Acceso limitado a recursos públicos

---

## 👥 Gestión de usuarios

- Cada profesor dispone de:
  - Usuario Linux
  - Usuario Samba
  - Carpeta privada en el NAS
- El alumnado **no tiene usuarios creados** en el sistema.
- La creación de usuarios del profesorado se automatiza mediante script.

---

## 🚀 Automatización

El proyecto incluye un script interactivo para la creación segura de usuarios del profesorado:
scripts/alta_profesor.sh

El script:
- Comprueba si el usuario ya existe
- Verifica carpetas locales y en el NAS
- Crea usuarios Linux y Samba si es necesario
- Aplica permisos correctos
- Muestra el estado final de la configuración

---

## 🔐 Seguridad

- No se exponen servicios directamente a Internet
- Acceso remoto exclusivamente mediante ZeroTier
- Separación estricta entre datos públicos y privados
- Uso de permisos mínimos necesarios
- Sin cuentas de alumnado en el sistema

---

## 📚 Documentación

Toda la documentación técnica se encuentra en la carpeta `docs/`.

Se recomienda comenzar por:

1. `00_resumen_proyecto.md`
2. `01_arquitectura_red.md`
3. `04_samba_usuarios_y_permisos.md`

---

## 🛠️ Requisitos

- Proxmox VE
- Sistema Linux (Ubuntu Server recomendado)
- NAS compatible con NFS
- Cliente ZeroTier
- Clientes Windows/Linux para acceso Samba

---

## 📌 Notas finales

Este proyecto está diseñado para ser:

- Reproducible
- Seguro
- Escalable
- Fácil de mantener
- Correctamente documentado para uso futuro

La documentación no solo describe **qué se hace**, sino **por qué se toman determinadas decisiones técnicas**.






