import type { Metadata } from "next";
import { LoginForm } from "@/modules/auth/components/LoginForm";

export const metadata: Metadata = { title: "Ingresar · ERP JADA" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; motivo?: string }>;
}) {
  const { next, motivo } = await searchParams;
  return <LoginForm next={next} motivo={motivo} />;
}
