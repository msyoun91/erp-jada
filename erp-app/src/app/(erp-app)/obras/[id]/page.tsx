import { notFound } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { accionDe } from "../../fichas";
import { fichaObra } from "./ficha";

// `?vincular={rol}` y `?estado={estado}`: los links de acción de Tareas abren
// la ficha con el panel o el cambio de estado a mano.
export default async function ObraPage(props: PageProps<"/obras/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success) notFound();
  const ficha = await fichaObra(id, accionDe(await props.searchParams));
  if (!ficha) notFound();
  return ficha;
}
