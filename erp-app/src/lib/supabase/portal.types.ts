// La base del portal (otro proyecto, MCP supabase-portal): generado con generate_typescript_types, solo el tipo Database.
// A mano: p_copia de portal_copiar admite null (cortar), que el generador no marca.
import type { Json } from "./database.types";

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      portal_links: {
        Row: {
          activo: boolean
          copia: string | null
          created_at: string
          huella: string
          id: string
          revision: number
          updated_at: string
          versiones: number[]
        }
        Insert: {
          activo?: boolean
          copia?: string | null
          created_at?: string
          huella: string
          id?: string
          revision: number
          updated_at?: string
          versiones?: number[]
        }
        Update: {
          activo?: boolean
          copia?: string | null
          created_at?: string
          huella?: string
          id?: string
          revision?: number
          updated_at?: string
          versiones?: number[]
        }
        Relationships: []
      }
      portal_monedas: {
        Row: {
          activo: boolean
          created_at: string
          fecha: string
          id: string
          moneda: string
          referencia: boolean
          updated_at: string
          valor: number
        }
        Insert: {
          activo?: boolean
          created_at?: string
          fecha: string
          id?: string
          moneda: string
          referencia: boolean
          updated_at?: string
          valor: number
        }
        Update: {
          activo?: boolean
          created_at?: string
          fecha?: string
          id?: string
          moneda?: string
          referencia?: boolean
          updated_at?: string
          valor?: number
        }
        Relationships: []
      }
      portal_visitas: {
        Row: {
          activo: boolean
          created_at: string
          dispositivo: string
          id: string
          link_id: string
          ultima: string
          updated_at: string
          version: number
        }
        Insert: {
          activo?: boolean
          created_at?: string
          dispositivo: string
          id?: string
          link_id: string
          ultima?: string
          updated_at?: string
          version: number
        }
        Update: {
          activo?: boolean
          created_at?: string
          dispositivo?: string
          id?: string
          link_id?: string
          ultima?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "portal_visitas_link_id_fkey"
            columns: ["link_id"]
            isOneToOne: false
            referencedRelation: "portal_links"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      portal_copiar: {
        Args: {
          p_copia: string | null
          p_huella: string
          p_revision: number
          p_versiones: number[]
        }
        Returns: undefined
      }
      portal_leer: { Args: { p_huella: string }; Returns: string }
      portal_monedas_guardar: { Args: { p_monedas: Json }; Returns: undefined }
      portal_monedas_leer: {
        Args: never
        Returns: {
          fecha: string
          moneda: string
          referencia: boolean
          valor: number
        }[]
      }
      portal_visitar: {
        Args: { p_dispositivo: string; p_huella: string; p_version: number }
        Returns: undefined
      }
      portal_visitas_de: {
        Args: { p_huellas: string[] }
        Returns: {
          dispositivos: number
          huella: string
          primera: string
          ultima: string
          version: number
          visitas: number
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}
