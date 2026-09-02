import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { UserRound } from "lucide-react";
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
    .select("nombre, email")
    .eq("id", user.id)
    .single();

  if (!perfil) redirect("/login");

  return (
    <div className="flex flex-col h-full">
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <UserRound size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Mi perfil
      </h1>
      <PerfilView nombre={perfil.nombre} email={perfil.email} />
    </div>
  );
}
