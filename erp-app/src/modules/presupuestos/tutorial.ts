import type { GuionTutorial } from "@/components/layout/Tutorial";

export const TUTORIAL_PRESUPUESTOS: GuionTutorial = {
  "/presupuestos": [
    {
      codigo: "presupuestos_tabs",
      titulo: "Armar, revisar y configurar",
      texto:
        "Presupuestos es donde se arman y se publican. Revisión técnica es para quien autoriza las alertas de los paquetes, y Configuración fija el tope de descuento y el vencimiento.",
    },
    {
      codigo: "presupuestos_ver_alta",
      titulo: "Todo presupuesto cuelga de una obra",
      texto:
        "«Nuevo presupuesto» te pide la obra: lo ve quien ve esa obra. Para un precio rápido sin guardar nada, usá la Calculadora.",
    },
    {
      codigo: "presupuestos_ver_filtros",
      titulo: "Lo que espera algo de vos",
      texto:
        "«Devueltas» son versiones que te rechazaron con un motivo: corregilas y volvé a pedir. Si autorizás, «Esperan mi autorización» junta los pedidos de tu equipo.",
    },
  ],
  "/presupuestos/[id]": [
    {
      codigo: "presupuestos_ficha_cabecera",
      titulo: "Aprobar o rechazar, cuando el cliente decide",
      texto:
        "Desde ⋯ registrás la aprobación (con la variante que eligió el cliente) o el rechazo con motivo. La obra cambia de estado sola. Aprobado o rechazado ya no se toca: solo se revierte.",
    },
    {
      codigo: "presupuestos_ficha_portal",
      titulo: "El cliente lo ve en el portal",
      texto:
        "Copiá el link y mandáselo: ve lo publicado, compara variantes y elige opcionales. Su elección te llega para aplicarla; él no confirma ni rechaza desde ahí.",
    },
    {
      codigo: "presupuestos_ficha_variante",
      titulo: "Variantes y versiones",
      texto:
        "Cada variante es una alternativa para el cliente (por ejemplo, con y sin mosquitero). Corregir crea una versión nueva: la publicada queda como estaba hasta que publiques la nueva.",
    },
  ],
  "/presupuestos/[id]/[id]": [
    {
      codigo: "presupuestos_version_cabecera",
      titulo: "IVA, opcionales y condiciones",
      texto:
        "El ⋯ de la versión define si el IVA va discriminado o incluido, cómo se ven los opcionales, y pasa todas las ventanas a precio de hoy o las mantiene como se cotizaron.",
    },
    {
      codigo: "presupuestos_version_seccion",
      titulo: "Secciones con su moneda",
      texto:
        "Cada sección tiene su moneda y su alícuota. Adentro van los renglones: un paquete del Catálogo con sus medidas, o un renglón a mano con descripción y precio.",
    },
    {
      codigo: "presupuestos_version_totales",
      titulo: "Totales por moneda",
      texto: "Una sección en dólares y otra en pesos dan dos totales: no se mezclan monedas en una suma.",
    },
    {
      codigo: "presupuestos_version_publicar",
      titulo: "Antes de publicar",
      texto:
        "Acá aparece lo que frena: un descuento sobre el tope o una ventana mantenida piden autorización del jefe, y una alerta del paquete, la de Técnica. Si un precio cambió en Catálogo desde que lo cargaste, te pide actualizarlo o mantenerlo.",
    },
  ],
  "/presupuestos/revision": [
    {
      codigo: "presupuestos_revision_lista",
      titulo: "Ventanas con alerta",
      texto:
        "Cada fila es una versión que no se publica hasta que Técnica la autorice. Ves las medidas completas, sin precios, obra ni cliente. Si la autorizás, vale mientras esa ventana no cambie.",
    },
  ],
  "/presupuestos/configuracion": [
    {
      codigo: "presupuestos_config_vigente",
      titulo: "Reglas para todos los presupuestos",
      texto:
        "Hasta cuánto descuento se da sin autorización, a cuántos días vence una versión publicada y qué monedas ve el cliente de referencia. Cambiar guarda la anterior en el historial.",
    },
  ],
};
