import { notFound, redirect } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeVerContactos } from "@/modules/contactos/permissions";
import { getFusionada } from "@/modules/contactos/queries";
import { fichaPersona } from "./ficha";

export default async function PersonaPage(props: PageProps<"/contactos/personas/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success) notFound();
  const ficha = await fichaPersona(id);
  if (ficha)
    return (
      <div className="flex flex-col gap-4">
        <Volver href="/contactos">Personas</Volver>
        {ficha}
      </div>
    );
  // Un link viejo a una que se fusionó y ya no se ve lleva a la que queda.
  const fusionada = (await puedeVerContactos()) ? await getFusionada("persona", id) : null;
  if (fusionada?.id) redirect(`/contactos/personas/${fusionada.id}`);
  notFound();
}
