import type { GuionTutorial, PasoTutorial } from "@/components/layout/Tutorial";

const POR_APROBAR: PasoTutorial = {
  codigo: "contactos_por_aprobar",
  titulo: "Altas que se parecen a otra",
  texto:
    "Si alguien carga un contacto parecido a uno que ya existe, queda congelado hasta que lo revises acá. El número es cuántas esperan.",
};

const HUERFANAS: PasoTutorial = {
  codigo: "contactos_huerfanas",
  titulo: "Contactos sin dueño activo",
  texto:
    "«Huérfanas» muestra lo que quedó de alguien que ya no usa Contactos. Abrilo y reasignalo para que no se pierda.",
};

export const TUTORIAL_CONTACTOS: GuionTutorial = {
  "/contactos": [
    {
      codigo: "contactos_tabs",
      titulo: "Personas y empresas, por separado",
      texto:
        "Una persona es de quien la cargó: es su agenda. Una empresa es del equipo de quien la cargó. Auditoría, si la tenés, muestra quién miró qué teléfono.",
    },
    {
      codigo: "contactos_persona_nueva",
      titulo: "Tu agenda",
      texto:
        "Las personas que cargás son tuyas: otro vendedor no las ve, salvo las que estén vinculadas a una obra que él también ve. Si se parece a una que ya existe, entra congelada hasta que la aprueben.",
    },
    POR_APROBAR,
    HUERFANAS,
    {
      codigo: "contactos_persona_lista",
      titulo: "Abrí la ficha",
      texto: "Un clic abre la persona: sus datos, sus empresas y las obras a las que está vinculada.",
    },
  ],
  "/contactos/empresas": [
    {
      codigo: "contactos_empresa_nueva",
      titulo: "Las empresas son del equipo",
      texto:
        "Una empresa la ve y la edita todo tu equipo, y los equipos con los que se compartió. No lleva razón social ni CUIT: se identifica por el nombre.",
    },
    POR_APROBAR,
    HUERFANAS,
    {
      codigo: "contactos_empresa_lista",
      titulo: "Compartida por otro equipo",
      texto: "Si abajo del nombre dice «Compartida por…», es de otro equipo que te la prestó: la podés usar como propia.",
    },
  ],
  "/contactos/personas/[id]": [
    {
      codigo: "contactos_persona_ver_contacto",
      titulo: "El teléfono se pide",
      texto:
        "Teléfono y email no están a la vista: «Ver contacto» los muestra y deja registrado quién los miró y cuándo.",
    },
    {
      codigo: "contactos_persona_cabecera",
      titulo: "El dueño y el menú ⋯",
      texto:
        "Abajo del nombre está el dueño. Desde ⋯ el dueño edita, transfiere la persona a otro o la desactiva; sus vínculos con obras quedan.",
    },
  ],
  "/contactos/empresas/[id]": [
    {
      codigo: "contactos_empresa_cabecera",
      titulo: "Compartir con otro equipo",
      texto:
        "Desde ⋯ la podés compartir: ese equipo la ve y la vincula como si fuera suya. Dejar de compartir no rompe los vínculos que ya hizo.",
    },
  ],
  "/contactos/por-aprobar": [
    {
      codigo: "contactos_aprobar_tarjeta",
      titulo: "Aprobar, rechazar o «es la misma»",
      texto:
        "Cada alta muestra los contactos parecidos y qué dato coincidió. Si es un duplicado, «Es la misma» la descarta y puede vincular la existente a la obra en su lugar. Quien la cargó recibe la respuesta.",
    },
  ],
  "/contactos/auditoria": [
    {
      codigo: "contactos_auditoria_filtros",
      titulo: "Período y persona",
      texto: "Elegí el período o buscá una persona para ver quién miró sus datos.",
    },
    {
      codigo: "contactos_auditoria_resumen",
      titulo: "La señal es mirar contactos ajenos",
      texto:
        "Cada fila es alguien que pidió ver un teléfono o email. Mirar los suyos es normal; muchos de otros dueños es lo que vale revisar. Nunca se muestra el dato en sí.",
    },
  ],
};
