import { notFound, redirect } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeVerContactos } from "@/modules/contactos/permissions";
import { getFusionada } from "@/modules/contactos/queries";
import { fichaPersona } from "./ficha";

export default async function PersonaPage(props: PageProps<"/contactos/personas/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success) notFound();
  const ficha = await fichaPersona(id);
  if (ficha) return ficha;
  // Un link viejo a una que se fusionó y ya no se ve lleva a la que queda.
  const fusionada = (await puedeVerContactos()) ? await getFusionada("persona", id) : null;
  if (fusionada?.id) redirect(`/contactos/personas/${fusionada.id}`);
  notFound();
}
