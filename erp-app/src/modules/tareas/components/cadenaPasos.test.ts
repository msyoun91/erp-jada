// Sin runner de tests en el repo: `node --test src/modules/tareas/components/cadenaPasos.test.ts`
// desde erp-app (Node 24 despoja los tipos solo). Mismo criterio que relacion.test.ts.
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { agruparCadenas, cadenasDePasos } from "./cadenaPasos.ts";
import type { EstadoTarea, TareaConAsignados } from "../types.ts";

function tarea(
  id: string,
  over: { paso_anterior_id?: string | null; estado?: EstadoTarea } = {},
): TareaConAsignados {
  return {
    id,
    paso_anterior_id: null,
    estado: "pendiente",
    tareas_asignados: [],
    ...over,
  } as unknown as TareaConAsignados;
}

// Una cadena de tres: a → b → c.
function cadenaDeTres(estados: [EstadoTarea, EstadoTarea, EstadoTarea] = ["pendiente", "pendiente", "pendiente"]) {
  return [
    tarea("a", { estado: estados[0] }),
    tarea("b", { paso_anterior_id: "a", estado: estados[1] }),
    tarea("c", { paso_anterior_id: "b", estado: estados[2] }),
  ];
}

test("una tarea suelta no entra al mapa", () => {
  assert.equal(cadenasDePasos([tarea("t1")]).size, 0);
});

test("la cadena numera posicion y total", () => {
  const info = cadenasDePasos(cadenaDeTres());
  assert.equal(info.size, 3);
  assert.deepEqual(
    ["a", "b", "c"].map((id) => info.get(id)?.posicion),
    [1, 2, 3],
  );
  assert.deepEqual(
    ["a", "b", "c"].map((id) => info.get(id)?.total),
    [3, 3, 3],
  );
});

test("bloqueada mira solo el paso previo inmediato", () => {
  const pendientes = cadenasDePasos(cadenaDeTres());
  assert.equal(pendientes.get("a")?.bloqueada, false);
  assert.equal(pendientes.get("b")?.bloqueada, true);
  assert.equal(pendientes.get("c")?.bloqueada, true);

  const primeraHecha = cadenasDePasos(cadenaDeTres(["completada", "pendiente", "pendiente"]));
  assert.equal(primeraHecha.get("b")?.bloqueada, false);
  // c sigue bloqueada aunque a esté completada: manda b, no el arranque.
  assert.equal(primeraHecha.get("c")?.bloqueada, true);
});

test("cancelada no desbloquea el paso siguiente", () => {
  const info = cadenasDePasos(cadenaDeTres(["cancelada", "pendiente", "pendiente"]));
  assert.equal(info.get("b")?.bloqueada, true);
});

test("con la previa fuera de la lista, el paso arranca bloqueado", () => {
  // b y c visibles, a no: b es raíz de la cadena visible, pero su
  // `paso_anterior_id` sigue apuntando a algo — el trigger la rechazaría.
  const info = cadenasDePasos([
    tarea("b", { paso_anterior_id: "a" }),
    tarea("c", { paso_anterior_id: "b" }),
  ]);
  assert.equal(info.get("b")?.bloqueada, true);
  assert.equal(info.get("b")?.posicion, 1);
  assert.equal(info.get("b")?.total, 2);
});

test("el orden de entrada no cambia la cadena", () => {
  const [a, b, c] = cadenaDeTres();
  const info = cadenasDePasos([c, a, b]);
  assert.deepEqual(
    info.get("a")?.cadena.map((t) => t.id),
    ["a", "b", "c"],
  );
});

test("la cadena se comparte por referencia entre sus pasos", () => {
  const info = cadenasDePasos(cadenaDeTres());
  assert.equal(info.get("a")?.cadena, info.get("c")?.cadena);
});

test("un ciclo en los datos no cuelga", () => {
  const info = cadenasDePasos([
    tarea("a", { paso_anterior_id: "b" }),
    tarea("b", { paso_anterior_id: "a" }),
  ]);
  // Ninguna es raíz: el ciclo entero queda afuera en vez de recorrerse infinito.
  assert.equal(info.size, 0);
});

test("agruparCadenas deja la cadena contigua donde apareció su primer miembro", () => {
  const [a, b, c] = cadenaDeTres();
  const suelta1 = tarea("s1");
  const suelta2 = tarea("s2");
  // Orden por temperatura: la cadena llega partida y con c antes que a.
  const orden = [suelta1, c, suelta2, a, b];
  const agrupadas = agruparCadenas(orden, cadenasDePasos([a, b, c]));
  assert.deepEqual(
    agrupadas.map((t) => t.id),
    ["s1", "a", "b", "c", "s2"],
  );
});

test("agruparCadenas no repite ni inventa filas", () => {
  const [a, b, c] = cadenaDeTres();
  const cadenas = cadenasDePasos([a, b, c]);
  // b filtrada de la lista visible: la cadena la conoce, la salida no la trae.
  const agrupadas = agruparCadenas([c, a], cadenas);
  assert.deepEqual(
    agrupadas.map((t) => t.id),
    ["a", "c"],
  );
});

test("agruparCadenas conserva el orden de las sueltas", () => {
  const sueltas = [tarea("s1"), tarea("s2"), tarea("s3")];
  const agrupadas = agruparCadenas(sueltas, cadenasDePasos(sueltas));
  assert.deepEqual(
    agrupadas.map((t) => t.id),
    ["s1", "s2", "s3"],
  );
});
