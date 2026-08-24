import type { TareaConAsignados } from "../types";

export type PasoEnCadena = {
  posicion: number;
  total: number;
  bloqueada: boolean;
  // Todos los pasos de la cadena en orden, compartido por referencia entre los
  // miembros: el panel muestra los previos sin volver a recorrer nada.
  cadena: TareaConAsignados[];
};

// "Bloqueada" no se guarda en la base (sql/017): se deriva del estado de la
// tarea previa. Este es el único lugar que lo calcula — la Lista, el panel de
// tarea y Misión leen de acá. El trigger `validar_paso_previo` es el que
// autoriza de verdad; esto solo decide qué mostrar.
//
// La cadena vive entera dentro de un hilo, así que da lo mismo pasarle las
// tareas de un hilo o la lista completa. Las tareas sueltas no entran al mapa.
export function cadenasDePasos(tareas: TareaConAsignados[]): Map<string, PasoEnCadena> {
  const porId = new Map(tareas.map((t) => [t.id, t]));
  const siguiente = new Map<string, TareaConAsignados>();
  for (const t of tareas) {
    if (t.paso_anterior_id) siguiente.set(t.paso_anterior_id, t);
  }

  const info = new Map<string, PasoEnCadena>();

  for (const raiz of tareas) {
    const esRaiz = raiz.paso_anterior_id === null || !porId.has(raiz.paso_anterior_id);
    if (!esRaiz) continue;
    if (raiz.paso_anterior_id === null && !siguiente.has(raiz.id)) continue;

    const cadena: TareaConAsignados[] = [];
    // Los ciclos son imposibles por construcción (`paso_anterior_id` es
    // inmutable, sql/017), pero un dato roto colgaría la pestaña: dos líneas de
    // seguro contra algo que no tiene vuelta atrás en el cliente.
    const vistos = new Set<string>();
    for (
      let actual: TareaConAsignados | undefined = raiz;
      actual && !vistos.has(actual.id);
      actual = siguiente.get(actual.id)
    ) {
      vistos.add(actual.id);
      cadena.push(actual);
    }

    cadena.forEach((paso, i) => {
      const previa = i === 0 ? null : cadena[i - 1];
      info.set(paso.id, {
        posicion: i + 1,
        total: cadena.length,
        cadena,
        // Sin previa a la vista pero con `paso_anterior_id`, no se puede
        // afirmar que esté desbloqueada y el trigger la va a rechazar igual:
        // se muestra bloqueada antes que ofrecer una acción que falla.
        bloqueada: previa ? previa.estado !== "completada" : paso.paso_anterior_id !== null,
      });
    });
  }

  return info;
}

// Una cadena mezclada por temperatura se lee como tareas sueltas y pierde lo
// único que la distingue de un hilo: el orden. Se respeta el orden que venga
// (temperatura), pero cada cadena queda contigua, arrancando donde apareció su
// primer miembro y siguiendo por posición.
export function agruparCadenas<T extends TareaConAsignados>(
  tareas: T[],
  cadenas: Map<string, PasoEnCadena>
): T[] {
  const porId = new Map(tareas.map((t) => [t.id, t]));
  const usadas = new Set<string>();
  const salida: T[] = [];

  for (const t of tareas) {
    if (usadas.has(t.id)) continue;
    const info = cadenas.get(t.id);
    if (!info) {
      usadas.add(t.id);
      salida.push(t);
      continue;
    }
    for (const paso of info.cadena) {
      const fila = porId.get(paso.id);
      if (!fila || usadas.has(fila.id)) continue;
      usadas.add(fila.id);
      salida.push(fila);
    }
  }

  return salida;
}
