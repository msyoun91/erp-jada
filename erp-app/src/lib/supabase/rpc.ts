import type { Database } from "./database.types";

type Funciones = Database["public"]["Functions"];

// El generador de tipos de Supabase pasó a declarar los argumentos de RPC como
// no-nulos. Es un cambio del lado del servidor, no del CLI: `gen types
// --project-id` y el MCP producen lo mismo, y el archivo commiteado antes traía
// `| null`. Pero los parámetros SQL sí aceptan NULL, y PostgREST los exige
// presentes cuando no tienen DEFAULT — mandar `null` es lo correcto y el tipo
// es el que miente.
//
// Esto acota la corrección a un solo lugar en vez de castear en cada llamada, y
// sigue chequeando nombre y tipo de cada campo. Si el generador vuelve a emitir
// `| null`, se borra el helper y las llamadas quedan igual.
export function argsRpc<F extends keyof Funciones>(args: {
  [K in keyof Funciones[F]["Args"]]: Funciones[F]["Args"][K] | null;
}): Funciones[F]["Args"] {
  return args as Funciones[F]["Args"];
}
