import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCandidatos, getNombres, getPersona } from "@/modules/contactos/queries";
import { PersonaView } from "@/modules/contactos/components/PersonaView";

export default async function PersonaPage(props: PageProps<"/contactos/personas/[id]">) {
  const { id } = await props.params;
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos()) || !idSchema.safeParse(id).success) notFound();

  const [datos, admin, nombres, candidatos] = await Promise.all([
    getPersona(id),
    puedeAdministrar(),
    getNombres(),
    getCandidatos(),
  ]);
  if (!datos) notFound();

  return <PersonaView {...datos} yo={yo} admin={admin} nombres={nombres} candidatos={candidatos} />;
}
