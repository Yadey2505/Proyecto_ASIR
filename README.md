# Proyecto_ASIR
# 🧪 Laboratorio de Virtualización con Proxmox

Este proyecto documenta la creación y configuración de un **laboratorio de virtualización** basado en **Proxmox VE**, con **acceso remoto seguro mediante VPN**, **despliegue automatizado por PXE** y un **servidor NAS con OpenMediaVault** para copias de seguridad, almacenamiento y compartición de datos.

El laboratorio está pensado como entorno de **aprendizaje, pruebas y administración de sistemas**, simulando una infraestructura real.

---

## 🎯 Objetivos

- Virtualizar servidores y servicios en un único host
- Acceder de forma remota y segura a la infraestructura
- Automatizar la instalación de sistemas operativos vía red
- Centralizar copias de seguridad y almacenamiento
- Practicar administración de sistemas, redes y virtualización

---

## 🏗️ Arquitectura del Laboratorio

- **Hipervisor**: Proxmox VE  
- **Acceso remoto**: VPN (WireGuard u OpenVPN)  
- **Despliegue de sistemas**: PXE  
- **Almacenamiento en red**: OpenMediaVault (NAS)  
- **Tecnologías**: KVM, LXC, SMB, NFS  

---

## 🖥️ Proxmox VE

Proxmox VE es el núcleo del laboratorio y permite:

- Gestión de máquinas virtuales (KVM)
- Uso de contenedores LXC
- Redes virtuales mediante bridges
- Snapshots y backups programados
- Administración completa vía interfaz web

Proxmox centraliza todos los servicios desplegados en el laboratorio.

---

## 🔐 Acceso Remoto por VPN

El acceso al laboratorio se realiza a través de una **VPN segura**, que permite:

- Administración remota del hipervisor
- Acceso a servicios internos desde el exterior
- Aislamiento y protección de la red local

Ventajas:
- Tráfico cifrado
- Autenticación por usuario
- Acceso seguro desde cualquier ubicación

---

## 🚀 Despliegue PXE

El servicio PXE permite instalar sistemas operativos sin medios físicos:

- Arranque de equipos por red
- Instalaciones rápidas y automatizadas
- Ideal para pruebas, reinstalaciones y laboratorios

Componentes habituales:
- Servidor DHCP
- Servidor TFTP
- Servidor HTTP/NFS para imágenes

---

## 💾 Servidor NAS con OpenMediaVault

OpenMediaVault se utiliza como **servidor NAS**, ofreciendo:

- Almacenamiento centralizado
- Copias de seguridad de Proxmox
- Compartición de archivos en red

Servicios disponibles:
- SMB/CIFS
- NFS
- FTP / SFTP
- Gestión de discos y RAID
- Snapshots y cuotas

---

## 🔄 Copias de Seguridad

- Backups automáticos desde Proxmox al NAS
- Almacenamiento de máquinas virtuales y contenedores
- Restauración rápida ante fallos o pruebas

---

## 📁 Estructura del Repositorio

