import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getCandidatos, getFusionada, getNombres, getPersona } from "@/modules/contactos/queries";
import { PersonaView } from "@/modules/contactos/components/PersonaView";

// La ficha de la persona, en su página y en Tareas al lado del paso.
// Sin persona visible, null.
export async function fichaPersona(id: string) {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) return null;

  const [datos, admin, nombres, candidatos] = await Promise.all([
    getPersona(id),
    puedeAdministrar(),
    getNombres(),
    getCandidatos(),
  ]);
  if (!datos) return null;
  const fusionada = datos.persona.fusionada_en ? await getFusionada("persona", id) : null;

  return <PersonaView {...datos} yo={yo} admin={admin} nombres={nombres} candidatos={candidatos} fusionada={fusionada} />;
}
