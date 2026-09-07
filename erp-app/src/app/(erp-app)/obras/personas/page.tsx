import { notFound } from "next/navigation";
import {
  puedeCrearPersona,
  puedeVerPersonas,
  puedeVerTodasLasPersonas,
} from "@/modules/obras/permissions";
import { getPersonas } from "@/modules/obras/queries";
import { PersonasView } from "@/modules/obras/components/PersonasView";

export default async function PersonasPage() {
  if (!(await puedeVerPersonas())) notFound();

  const [personas, crear, todas] = await Promise.all([
    getPersonas(),
    puedeCrearPersona(),
    puedeVerTodasLasPersonas(),
  ]);

  return <PersonasView personas={personas} puedeCrear={crear} veTodas={todas} />;
}
