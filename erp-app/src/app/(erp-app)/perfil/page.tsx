import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Modulo } from "@/components/layout/Modulo";
import { createClient } from "@/lib/supabase/server";
import { PerfilView } from "@/modules/auth/components/PerfilView";

export const metadata: Metadata = { title: "Mi perfil · ERP JADA" };

// Única ruta de (erp-app) sin chequeo de permiso: editar la propia cuenta no
// es algo que se autorice, es lo que significa tener cuenta. La excepción a la
// regla de submódulos está registrada en decisiones/auth.md, y la barrera real es
// RLS por columna (`sql/022`) — nadie puede tocar acá una fila que no sea suya.
export default async function PerfilPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: perfil } = await supabase
    .from("usuarios")
    .select("nombre, email, telefono")
    .eq("id", user.id)
    .single();

  if (!perfil) redirect("/login");

  return (
    <Modulo modulo="perfil">
      <PerfilView nombre={perfil.nombre} email={perfil.email} telefono={perfil.telefono} />
    </Modulo>
  );
}
