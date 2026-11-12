import type { GuionTutorial } from "@/components/layout/Tutorial";

export const TUTORIAL_OBRAS: GuionTutorial = {
  "/obras": [
    {
      codigo: "obras_ver_nueva",
      titulo: "La obra es de quien la carga",
      texto:
        "Quedás como responsable. Si se parece a una obra que ya existe, entra congelada hasta que alguien la apruebe: así no hay dos vendedores con la misma obra.",
    },
    {
      codigo: "obras_por_aprobar",
      titulo: "Altas por aprobar",
      texto: "Las obras que se parecen a otra esperan acá tu decisión. El número es cuántas hay.",
    },
    {
      codigo: "obras_ver_filtro",
      titulo: "Abiertas por defecto",
      texto:
        "La lista arranca con lo que está en juego: idea, en búsqueda y en cotización. Cambiá a Contratadas o Perdidas para ver el resto.",
    },
    {
      codigo: "obras_ver_lista",
      titulo: "Las tuyas y en las que participás",
      texto:
        "Ves las obras donde sos responsable o participante. Un clic abre la ficha con sus contactos, presupuestos y tareas.",
    },
  ],
  "/obras/todas": [
    {
      codigo: "obras_todas_filtro",
      titulo: "Todas, también las huérfanas",
      texto:
        "Acá están las obras de todos, incluidas las desactivadas. «Huérfanas» son las de un responsable que ya no usa Obras: abrilas y transferilas.",
    },
  ],
  "/obras/[id]": [
    {
      codigo: "obras_ficha_estado",
      titulo: "El estado se cambia acá",
      texto:
        "Un clic en el estado lo cambia. Con presupuestos, la base lo mueve sola: el primero publicado la pasa a cotización y el primero aprobado, a contratada.",
    },
    {
      codigo: "obras_ficha_participantes",
      titulo: "Compartir la obra",
      texto:
        "Un participante ve y trabaja la obra como el responsable, pero no ve la comisión del referente, no suma a otros ni la transfiere.",
    },
  ],
  "/obras/por-aprobar": [
    {
      codigo: "obras_aprobar_tarjeta",
      titulo: "Aprobar, rechazar o «es la misma»",
      texto:
        "Cada alta muestra las obras parecidas. Si es la misma, quien la cargó se suma a la existente en vez de duplicarla. Rechazar pide un motivo, que le llega a quien la cargó.",
    },
  ],
};
