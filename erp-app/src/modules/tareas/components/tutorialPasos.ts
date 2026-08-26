// Guion del tutorial guiado del módulo, por vista. El `codigo` es a la vez la
// clave que se guarda en `usuario_tutorial.paso` y el selector del elemento
// que se señala (`[data-tour="<codigo>"]`): un solo identificador, no dos que
// puedan desincronizarse.
//
// Un paso cuyo ancla no existe en el DOM se saltea y queda sin ver: así lo
// que depende de un permiso, de un filtro prendido o de que haya datos se
// explica recién cuando aparece, no antes.
export type PasoTutorial = {
  codigo: string;
  titulo: string;
  texto: string;
};

const LISTA: PasoTutorial[] = [
  {
    codigo: "tareas_tabs",
    titulo: "Cinco vistas de lo mismo",
    texto:
      "Lista es el panorama completo. Misión te pasa tus tareas de a una. Proyectos agrupa el trabajo por obra o cliente, Plantillas guarda cadenas de pasos que se repiten, y Auditoría muestra qué se completó.",
  },
  {
    codigo: "tareas_lista_usuario",
    titulo: "Arranca filtrado en vos",
    texto:
      "La Lista abre mostrando lo tuyo. Cambiá a otro usuario o a «Todos los usuarios» para ver el panorama del equipo — no muestra nada que no pudieras ver igual.",
  },
  {
    codigo: "tareas_lista_relacion",
    titulo: "Míos no es lo mismo que Involucrado",
    texto:
      "«Míos» es donde sos responsable: la tarea es tuya. «Involucrado» es donde estás asignado sin ser el responsable. Son grupos separados, nunca se pisan.",
  },
  {
    codigo: "tareas_lista_terminadas",
    titulo: "Lo terminado se esconde solo",
    texto:
      "Prendido, la Lista muestra trabajo y no historial: esconde tareas terminadas e hilos cerrados. Apagalo cuando busques algo que ya se hizo.",
  },
  {
    codigo: "tareas_lista_hilo",
    titulo: "Un hilo agrupa tareas que van juntas",
    texto:
      "Si el trabajo son varios pasos con un mismo objetivo, hacé un hilo. Sus pasos pueden encadenarse: cada uno espera a que se complete el anterior.",
  },
  {
    codigo: "tareas_lista_tarea",
    titulo: "Una tarea suelta no necesita hilo",
    texto:
      "Para algo que se hace de una. Si después resulta que era más largo, se convierte en hilo desde el panel de la tarea — no hay que rehacerla.",
  },
  {
    codigo: "tareas_lista_isla",
    titulo: "El título abre todo",
    texto:
      "Cada fila muestra estado, temperatura y quién está asignado. Un clic en el título abre el panel derecho: ahí se cambia el estado, se agregan notas y se asigna gente.",
  },
];

const MISION: PasoTutorial[] = [
  {
    codigo: "tareas_mision_cola",
    titulo: "De a una, por temperatura",
    texto:
      "Misión arma la cola con lo tuyo que está activo y no bloqueado, lo más caliente primero. Las flechas ← → del teclado también avanzan.",
  },
  {
    codigo: "tareas_mision_bloqueadas",
    titulo: "Lo que espera no entra en la cola",
    texto:
      "Una tarea encadenada no aparece hasta que se complete su paso previo. Acá abajo se ve qué está frenando qué, y se puede abrir igual.",
  },
];

const PROYECTOS: PasoTutorial[] = [
  {
    codigo: "tareas_proyectos_miembro",
    titulo: "Filtra por miembro, no por quién lo ve",
    texto:
      "Ser miembro es trabajar en el proyecto. Ver el proyecto es otro eje — un proyecto público lo ve todo el mundo, pero solo sus miembros pueden recibir tareas ahí.",
  },
  {
    codigo: "tareas_proyectos_crear",
    titulo: "Un proyecto necesita miembros",
    texto:
      "Los miembros son quiénes pueden recibir tareas del proyecto. Todo proyecto necesita al menos uno, así que se eligen al crearlo.",
  },
  {
    codigo: "tareas_proyectos_lista",
    titulo: "El proyecto abre su panel",
    texto:
      "Un clic en el nombre muestra los hilos y tareas que cuelgan del proyecto, y desde ahí se administran los miembros.",
  },
];

const PLANTILLAS: PasoTutorial[] = [
  {
    codigo: "tareas_plantillas_crear",
    titulo: "Una plantilla es una cadena de pasos",
    texto:
      "Guardá acá el trabajo que se repite igual. Al usarla crea todas las tareas de una, encadenadas en el orden que tengan los pasos.",
  },
  {
    codigo: "tareas_plantillas_lista",
    titulo: "El orden de los pasos es la regla",
    texto:
      "Un clic en el nombre abre la plantilla para editarla. Los pasos se reordenan con ↑↓ — el orden decide qué espera a qué.",
  },
];

const AUDITORIA: PasoTutorial[] = [
  {
    codigo: "tareas_auditoria_filtros",
    titulo: "Qué se completó y cuándo",
    texto:
      "El rango de fechas y el usuario viajan en la dirección de la página: el recorte que estás mirando se puede compartir tal cual.",
  },
  {
    codigo: "tareas_auditoria_pendientes",
    titulo: "Lo completado no es todo el cuadro",
    texto:
      "Al elegir un usuario aparece además lo que tiene pendiente. Sin eso, la auditoría solo cuenta lo que salió bien.",
  },
];

export const PASOS_POR_RUTA: Record<string, PasoTutorial[]> = {
  "/tareas": LISTA,
  "/tareas/mision": MISION,
  "/tareas/proyectos": PROYECTOS,
  "/tareas/plantillas": PLANTILLAS,
  "/tareas/auditoria": AUDITORIA,
};
