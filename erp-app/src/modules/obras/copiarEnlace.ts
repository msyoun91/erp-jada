import { toast } from "sonner";

// Acceso directo a la ficha. La URL ya funcionaba como enlace profundo —el
// middleware manda a /login con `next` y vuelve— pero no había forma de
// sacarla de la app sin copiarla de la barra del navegador.
export async function copiarEnlace(ruta: string) {
  const url = `${window.location.origin}${ruta}`;
  try {
    await navigator.clipboard.writeText(url);
    toast.success("Enlace copiado");
  } catch {
    // El portapapeles pide contexto seguro y permiso. Si no está, mostrar la
    // URL es mejor que un error que no deja hacer nada.
    toast.info(url, { duration: 15000 });
  }
}
