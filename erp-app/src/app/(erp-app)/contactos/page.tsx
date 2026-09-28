import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeAdministrar, puedeVerContactos } from "@/modules/contactos/permissions";
import { getNombres, getPersonas } from "@/modules/contactos/queries";
import { ContactosView } from "@/modules/contactos/components/ContactosView";

export default async function PersonasPage() {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerContactos())) notFound();

  const todas = await puedeAdministrar();
  const [personas, nombres] = await Promise.all([getPersonas({ todas, yo }), getNombres()]);

  return (
    <ContactosView
      tipo="persona"
      filas={personas.map((p) => ({
        id: p.id,
        nombre: p.nombre,
        detalle: todas ? (p.responsable_id === yo ? "Vos" : (nombres[p.responsable_id] ?? null)) : null,
        activo: p.activo,
      }))}
    />
  );
}
