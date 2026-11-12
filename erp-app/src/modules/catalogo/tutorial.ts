import type { GuionTutorial, PasoTutorial } from "@/components/layout/Tutorial";

// /catalogo abre la primera pestaña que el usuario tiene: el paso de las pestañas va en todas.
const TABS: PasoTutorial = {
  codigo: "catalogo_tabs",
  titulo: "Qué se vende y cuánto cuesta",
  texto:
    "Paquetes es lo que se vende: un despiece de piezas y materiales. Insumos y Servicios fijos son sus costos, y Servicios en % lo que se suma encima del despiece.",
};

export const TUTORIAL_CATALOGO: GuionTutorial = {
  "/catalogo/paquetes": [
    TABS,
    {
      codigo: "catalogo_paquetes_revisar",
      titulo: "Versiones que esperan tu OK",
      texto:
        "Técnica envía cada versión a revisión. Abrila, probá el precio con sus casos y aprobala o devolvela con un motivo. Hasta que la aprobás, sigue a la venta la anterior.",
    },
    {
      codigo: "catalogo_paquetes_nuevo",
      titulo: "Un paquete nace en borrador",
      texto:
        "Lo armás en una versión borrador, sin apuro: nadie lo vende hasta que se envía a revisión y el gerente la aprueba.",
    },
    {
      codigo: "catalogo_paquetes_referencia",
      titulo: "Precios de referencia",
      texto: "El precio de cada paquete hoy contra hace un tiempo, con la misma versión: lo que cambió viene de costos, porcentajes y tipo de cambio.",
    },
    {
      codigo: "catalogo_paquetes_estado",
      titulo: "A la venta por defecto",
      texto:
        "«Sin publicar» son paquetes que todavía no tienen ninguna versión aprobada; «De baja», los que se sacaron de la venta, a mano o porque se dio de baja algo que usaban.",
    },
  ],
  "/catalogo/insumos": [
    TABS,
    {
      codigo: "catalogo_insumo_nuevo",
      titulo: "Un insumo, varios colores",
      texto:
        "Cada color es una variante con su propio costo. Se edita libremente hasta que una versión que lo usa se envía a revisión; después solo el costo, las variantes y la baja.",
    },
    {
      codigo: "catalogo_insumo_costos",
      titulo: "Costos pendientes",
      texto:
        "Junta los insumos y colores que todavía no tienen costo, para cargarlos de una. Cada costo lleva su fecha y su moneda.",
    },
  ],
  "/catalogo/fijos": [
    TABS,
    {
      codigo: "catalogo_servicio_nuevo",
      titulo: "Servicios con costo fijo",
      texto:
        "Mano de obra, flete, colocación: lo que se cobra por unidad, metro o metro cuadrado. Entra al despiece como un insumo, sin color.",
    },
    {
      codigo: "catalogo_servicio_costos",
      titulo: "Costos pendientes",
      texto: "Junta los servicios que todavía no tienen costo, para cargarlos de una.",
    },
  ],
  "/catalogo/porcentajes": [
    TABS,
    {
      codigo: "catalogo_porcentajes_pasos",
      titulo: "Tres pasos, en orden",
      texto:
        "El paso 1 se calcula sobre el despiece, el 2 sobre el subtotal y el 3 sobre el precio final. Dentro de un mismo paso ninguno se calcula sobre otro. Cada cambio queda en la historia y se puede revertir.",
    },
  ],
  "/catalogo/paquetes/versiones/[id]": [
    {
      codigo: "catalogo_version_cabecera",
      titulo: "Borrador, en revisión, publicada",
      texto:
        "Técnica edita el borrador y lo envía; el gerente lo aprueba o lo devuelve. Al aprobarla, la versión anterior queda obsoleta. Los botones de las otras versiones llevan a su historia.",
    },
    {
      codigo: "catalogo_version_probar",
      titulo: "Probalo como un vendedor",
      texto: "Cargá medidas y elecciones y tocá Calcular: ves el despiece (y el precio, si aprobás) sin guardar nada.",
    },
    {
      codigo: "catalogo_version_casos",
      titulo: "Casos de prueba",
      texto:
        "Toda versión necesita al menos uno para enviarse. Son los datos con los que quien aprueba revisa la versión antes de publicarla.",
    },
  ],
  "/catalogo/paquetes/versiones/[id]/editar": [
    {
      codigo: "catalogo_editor_variables",
      titulo: "Lo que pregunta el paquete",
      texto:
        "Las variables sueltas valen para todo el paquete (ancho, alto). Las que carga el vendedor son las preguntas del presupuesto; las demás se calculan con fórmula.",
    },
    {
      codigo: "catalogo_editor_piezas",
      titulo: "Piezas armadas y sus materiales",
      texto:
        "Cada pieza tiene su cantidad y sus materiales: un insumo o un servicio fijo, con medida y condiciones. Una pieza opcional es la que elige el vendedor.",
    },
  ],
};
