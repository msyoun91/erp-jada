import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
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
  // La vuelta va acá y no en `ObraView`: la misma ficha se abre al lado de un paso de Tareas.
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/obras">Obras</Volver>
      {ficha}
    </div>
  );
}
