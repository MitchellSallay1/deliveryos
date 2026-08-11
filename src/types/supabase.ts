/**
 * Database types derived from supabase/migrations (Phase 4).
 * Regenerate when linked: npm run gen:types
 */
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type CompanyStatus = 'pending' | 'active' | 'suspended'
export type CompanyBusinessType = 'logistics_provider' | 'merchant' | 'hybrid'
export type CompanyRole = 'company_owner' | 'dispatcher' | 'rider' | 'support_staff'
export type RiderStatus = 'available' | 'busy' | 'offline' | 'suspended'
export type DeliveryStatus =
  | 'pending'
  | 'assigned'
  | 'accepted'
  | 'picked_up'
  | 'in_transit'
  | 'delivered'
  | 'failed'
  | 'cancelled'
export type PaymentStatus = 'pending' | 'collected' | 'deposited' | 'reconciled'
export type CommerceVendorState = 'draft' | 'pending_review' | 'active' | 'suspended' | 'rejected'
export type CommerceProductStatus = 'draft' | 'active' | 'paused'
export type CommerceOrderPaymentStatus = 'pending_payment' | 'paid' | 'payment_failed' | 'refund_pending' | 'refunded'
export type CommercePaymentMethod = 'cod' | 'mtn_momo' | 'orange_money'
export type CommerceOrderFulfillmentStatus =
  | 'awaiting_vendor'
  | 'vendor_accepted'
  | 'vendor_rejected'
  | 'preparing'
  | 'ready_for_pickup'
  | 'handed_to_carrier'
  | 'completed'
  | 'cancelled'
export type CompanySubscriptionStatus =
  | 'trialing'
  | 'active'
  | 'past_due'
  | 'suspended'
  | 'cancelled'
  | 'expired'
export type InvoiceStatus = 'draft' | 'issued' | 'paid' | 'overdue' | 'cancelled'
export type BillingPaymentMethod =
  | 'cash'
  | 'mtn_momo'
  | 'orange_money'
  | 'bank_transfer'
  | 'other'

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string | null
          phone: string | null
          phone_normalized: string | null
          avatar_url: string | null
          is_super_admin: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name?: string | null
          phone?: string | null
          phone_normalized?: string | null
          avatar_url?: string | null
          is_super_admin?: boolean
        }
        Update: {
          full_name?: string | null
          phone?: string | null
          phone_normalized?: string | null
          avatar_url?: string | null
          is_super_admin?: boolean
        }
        Relationships: []
      }
      companies: {
        Row: {
          id: string
          name: string
          slug: string
          logo_url: string | null
          phone: string
          email: string
          address: string | null
          status: CompanyStatus
          subscription_id: string
          /** Generated (sms_credits_included + sms_credits_purchased) — read-only, cannot be inserted/updated directly. */
          sms_credits: number
          sms_credits_included: number
          sms_credits_purchased: number
          allow_smartphone_riders?: boolean
          allow_button_phone_riders?: boolean
          enable_rider_sms?: boolean
          enable_rider_ussd?: boolean
          require_otp_button_phone_delivery?: boolean
          created_at: string
          updated_at: string
          business_type: CompanyBusinessType
          marketplace_suspended: boolean
          default_branch_id?: string | null
        }
        Insert: {
          id?: string
          name: string
          slug: string
          phone: string
          email: string
          address?: string | null
          status?: CompanyStatus
          subscription_id: string
        }
        Update: {
          name?: string
          slug?: string
          phone?: string
          email?: string
          address?: string | null
          status?: CompanyStatus
          subscription_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'companies_subscription_id_fkey'
            columns: ['subscription_id']
            referencedRelation: 'subscriptions'
            referencedColumns: ['id']
          },
        ]
      }
      company_users: {
        Row: {
          id: string
          company_id: string
          user_id: string
          role: CompanyRole
          is_active: boolean
          created_at: string
        }
        Insert: {
          id?: string
          company_id: string
          user_id: string
          role: CompanyRole
          is_active?: boolean
        }
        Update: {
          role?: CompanyRole
          is_active?: boolean
        }
        Relationships: []
      }
      company_invitations: {
        Row: {
          id: string
          company_id: string
          email: string
          role: CompanyRole
          token: string
          invited_by: string
          expires_at: string
          accepted_at: string | null
          revoked_at: string | null
          created_at: string
        }
        Insert: {
          id?: string
          company_id: string
          email: string
          role: CompanyRole
          token: string
          invited_by: string
          expires_at: string
        }
        Update: {
          accepted_at?: string | null
          revoked_at?: string | null
        }
        Relationships: []
      }
      riders: {
        Row: {
          id: string
          company_id: string
          user_id: string | null
          rider_code: string
          full_name: string
          phone: string
          status: RiderStatus
          access_mode?: 'smartphone' | 'button_phone' | 'both'
          invite_code?: string | null
          sms_channel_enabled?: boolean
          ussd_channel_enabled?: boolean
          phone_normalized?: string | null
          completed_deliveries: number
          rating: number
          created_at: string
          updated_at: string
        }
        Insert: {
          company_id: string
          user_id?: string | null
          rider_code: string
          full_name: string
          phone: string
          status?: RiderStatus
          access_mode?: 'smartphone' | 'button_phone' | 'both'
          sms_channel_enabled?: boolean
          ussd_channel_enabled?: boolean
        }
        Update: {
          user_id?: string | null
          full_name?: string
          phone?: string
          status?: RiderStatus
          access_mode?: 'smartphone' | 'button_phone' | 'both'
          sms_channel_enabled?: boolean
          ussd_channel_enabled?: boolean
        }
        Relationships: []
      }
      customers: {
        Row: {
          id: string
          company_id: string
          full_name: string
          phone: string
          address: string | null
          landmark: string | null
          notes: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          company_id: string
          full_name: string
          phone: string
          address?: string | null
          landmark?: string | null
          notes?: string | null
        }
        Update: {
          full_name?: string
          phone?: string
          address?: string | null
          landmark?: string | null
          notes?: string | null
        }
        Relationships: []
      }
      deliveries: {
        Row: {
          id: string
          company_id: string
          tracking_code: string
          pickup_business_name: string
          pickup_address: string
          customer_id: string | null
          customer_name: string
          customer_phone: string
          destination_address: string
          package_description: string | null
          amount_to_collect_lrd_cents: number
          delivery_fee_lrd_cents: number
          status: DeliveryStatus
          rider_id: string | null
          assigned_at: string | null
          accepted_at: string | null
          picked_up_at: string | null
          in_transit_at: string | null
          delivered_at: string | null
          failed_at: string | null
          cancelled_at: string | null
          failure_reason: string | null
          proof_method?: string | null
          rider_job_sms_status?: string | null
          rider_job_sms_sent_at?: string | null
          last_completion_channel?: string | null
          created_by: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      delivery_photos: {
        Row: {
          id: string
          company_id: string
          delivery_id: string
          storage_path: string
          uploaded_by: string | null
          created_at: string
        }
        Insert: {
          company_id: string
          delivery_id: string
          storage_path: string
          uploaded_by?: string | null
        }
        Update: Record<string, never>
        Relationships: []
      }
      payments: {
        Row: {
          id: string
          company_id: string
          delivery_id: string
          amount_lrd_cents: number
          status: PaymentStatus
          collected_by: string | null
          collected_at: string | null
          deposited_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: [
          {
            foreignKeyName: 'payments_delivery_id_fkey'
            columns: ['delivery_id']
            referencedRelation: 'deliveries'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'payments_company_id_fkey'
            columns: ['company_id']
            referencedRelation: 'companies'
            referencedColumns: ['id']
          },
        ]
      }
      sms_logs: {
        Row: {
          id: string
          company_id: string
          direction: 'outbound' | 'inbound'
          phone: string
          body: string
          credits_used: number
          delivery_id: string | null
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      notification_logs: {
        Row: {
          id: string
          company_id: string | null
          channel: string
          recipient: string
          subject: string | null
          body: string
          status: string
          metadata: Json
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      subscriptions: {
        Row: {
          id: string
          slug: string
          name: string
          max_riders: number
          max_deliveries_per_month: number | null
          price_lrd_cents: number
          currency: string
          monthly_sms_allowance: number
          proof_of_delivery: boolean
          advanced_reports: boolean
          api_access: boolean
          gps_tracking: boolean
          custom_branding: boolean
          is_active: boolean
          features: Json
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      company_subscriptions: {
        Row: {
          id: string
          company_id: string
          plan_id: string
          status: CompanySubscriptionStatus
          starts_at: string
          current_period_start: string
          current_period_end: string
          trial_ends_at: string | null
          cancelled_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      invoices: {
        Row: {
          id: string
          invoice_number: string
          company_id: string
          company_subscription_id: string | null
          plan_id: string
          billing_period_start: string
          billing_period_end: string
          amount_cents: number
          currency: string
          status: InvoiceStatus
          issued_at: string | null
          due_at: string | null
          paid_at: string | null
          payment_reference: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      subscription_billing_payments: {
        Row: {
          id: string
          company_id: string
          invoice_id: string | null
          amount_cents: number
          currency: string
          payment_method: BillingPaymentMethod
          reference: string | null
          paid_at: string
          billing_period_start: string | null
          billing_period_end: string | null
          recorded_by: string
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      audit_logs: {
        Row: {
          id: string
          actor_user_id: string | null
          company_id: string | null
          action: string
          entity_type: string
          entity_id: string | null
          metadata: Json
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      provider_marketplace_profiles: {
        Row: {
          company_id: string
          marketplace_enabled: boolean
          service_description: string | null
          service_phone: string | null
          service_email: string | null
          service_regions: Json
          accepting_jobs: boolean
          minimum_delivery_fee_lrd_cents: number
          maximum_service_distance_km: number | null
          rating_visible: boolean
          business_hours: Json
          admin_marketplace_disabled: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      store_profiles: {
        Row: {
          company_id: string
          slug: string
          display_name: string
          description: string | null
          logo_url: string | null
          banner_url: string | null
          business_hours: Json
          allow_cash_on_delivery: boolean
          status: CommerceVendorState
          status_reason: string | null
          reviewed_by: string | null
          reviewed_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      product_categories: {
        Row: {
          id: string
          company_id: string
          name: string
          sort_order: number
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      products: {
        Row: {
          id: string
          company_id: string
          category_id: string | null
          name: string
          description: string | null
          price_lrd_cents: number
          currency: string
          status: CommerceProductStatus
          tracks_inventory: boolean
          sort_order: number
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      product_images: {
        Row: {
          id: string
          product_id: string
          company_id: string
          storage_path: string
          sort_order: number
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      product_option_groups: {
        Row: {
          id: string
          product_id: string
          company_id: string
          name: string
          selection_type: string
          is_required: boolean
          sort_order: number
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      product_options: {
        Row: {
          id: string
          option_group_id: string
          company_id: string
          name: string
          price_delta_lrd_cents: number
          is_active: boolean
          sort_order: number
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      product_stock: {
        Row: {
          product_id: string
          company_id: string
          quantity_on_hand: number
          quantity_reserved: number
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      commerce_orders: {
        Row: {
          id: string
          order_number: string
          customer_id: string
          vendor_company_id: string
          cart_id: string | null
          subtotal_lrd_cents: number
          delivery_fee_lrd_cents: number
          total_lrd_cents: number
          currency: string
          payment_method: CommercePaymentMethod
          payment_status: CommerceOrderPaymentStatus
          fulfillment_status: CommerceOrderFulfillmentStatus
          customer_name: string
          customer_phone: string
          delivery_address: string | null
          delivery_area_summary: string | null
          delivery_latitude: number | null
          delivery_longitude: number | null
          delivery_instructions: string | null
          delivery_id: string | null
          delivery_request_id: string | null
          cancelled_at: string | null
          cancellation_reason: string | null
          created_at: string
          updated_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      commerce_order_items: {
        Row: {
          id: string
          order_id: string
          product_id: string | null
          product_name: string
          unit_price_lrd_cents: number
          quantity: number
          selected_options: Json
          line_total_lrd_cents: number
          created_at: string
        }
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: {
      create_company_with_owner: {
        Args: {
          p_name: string
          p_phone: string
          p_email: string
          p_address?: string | null
          p_business_type?: CompanyBusinessType
        }
        Returns: string
      }
      complete_pending_onboarding: {
        Args: Record<string, never>
        Returns: Json
      }
      sync_profile_from_auth_user: {
        Args: Record<string, never>
        Returns: Database['public']['Tables']['profiles']['Row']
      }
      finalize_phone_workspace: {
        Args: {
          p_full_name: string
          p_company_name: string
          p_business_type: CompanyBusinessType
          p_company_phone?: string | null
          p_company_email?: string | null
        }
        Returns: Json
      }
      ensure_initial_company_subscription: {
        Args: { p_company_id: string }
        Returns: Database['public']['Tables']['company_subscriptions']['Row']
      }
      create_delivery: {
        Args: {
          p_company_id: string
          p_pickup_business_name: string
          p_pickup_address: string
          p_customer_name: string
          p_customer_phone: string
          p_destination_address: string
          p_package_description?: string | null
          p_amount_to_collect_lrd_cents?: number
          p_delivery_fee_lrd_cents?: number
          p_customer_id?: string | null
          p_delivery_zone_id?: string | null
          p_fee_manual_override?: boolean
        }
        Returns: Database['public']['Tables']['deliveries']['Row']
      }
      assign_delivery_rider: {
        Args: { p_delivery_id: string; p_rider_id: string }
        Returns: Database['public']['Tables']['deliveries']['Row']
      }
      resend_rider_job_sms: {
        Args: { p_delivery_id: string }
        Returns: boolean
      }
      update_company_rider_channel_settings: {
        Args: { p_company_id: string; p_settings: Json }
        Returns: Database['public']['Tables']['companies']['Row']
      }
      transition_delivery_status: {
        Args: {
          p_delivery_id: string
          p_to_status: DeliveryStatus
          p_note?: string | null
        }
        Returns: Database['public']['Tables']['deliveries']['Row']
      }
      rider_transition_delivery_status: {
        Args: {
          p_delivery_id: string
          p_to_status: DeliveryStatus
          p_note?: string | null
        }
        Returns: Database['public']['Tables']['deliveries']['Row']
      }
      get_delivery_tracking: {
        Args: { p_tracking_code: string }
        Returns: {
          tracking_code: string
          status: DeliveryStatus
          company_name: string
          pickup_area: string
          destination_area: string
          updated_at: string
          status_timeline: Json
        }[]
      }
      get_workspace_report: {
        Args: { p_company_id: string; p_period?: string }
        Returns: Json
      }
      get_company_delivery_trend: {
        Args: { p_company_id: string; p_days?: number }
        Returns: Json
      }
      create_company_invitation: {
        Args: {
          p_company_id: string
          p_role: CompanyRole
          p_email?: string | null
          p_phone?: string | null
        }
        Returns: Json
      }
      accept_company_invitation: {
        Args: { p_token: string }
        Returns: Json
      }
      revoke_company_invitation: {
        Args: { p_invitation_id: string }
        Returns: undefined
      }
      list_company_team: {
        Args: { p_company_id: string }
        Returns: Json
      }
      list_company_invitations: {
        Args: { p_company_id: string }
        Returns: Json
      }
      get_invitation_by_token: {
        Args: { p_token: string }
        Returns: Json
      }
      set_company_member_active: {
        Args: { p_membership_id: string; p_is_active: boolean }
        Returns: Database['public']['Tables']['company_users']['Row']
      }
      update_company_member_role: {
        Args: { p_membership_id: string; p_role: CompanyRole }
        Returns: Database['public']['Tables']['company_users']['Row']
      }
      mark_payment_deposited: {
        Args: { p_payment_id: string }
        Returns: Database['public']['Tables']['payments']['Row']
      }
      mark_payment_reconciled: {
        Args: { p_payment_id: string }
        Returns: Database['public']['Tables']['payments']['Row']
      }
      register_delivery_photo: {
        Args: {
          p_company_id: string
          p_delivery_id: string
          p_storage_path: string
        }
        Returns: Database['public']['Tables']['delivery_photos']['Row']
      }
      claim_rider_profile: {
        Args: { p_company_id: string; p_rider_code: string }
        Returns: Database['public']['Tables']['riders']['Row']
      }
      link_rider_account: {
        Args: { p_rider_code?: string | null; p_invite_code?: string | null }
        Returns: Json
      }
      regenerate_rider_invite_code: {
        Args: { p_rider_id: string }
        Returns: Database['public']['Tables']['riders']['Row']
      }
      get_rider_invite_preview: {
        Args: { p_invite_code: string }
        Returns: Json
      }
      set_rider_user_id: {
        Args: { p_rider_id: string; p_user_id: string }
        Returns: Database['public']['Tables']['riders']['Row']
      }
      admin_add_sms_credits: {
        Args: {
          p_company_id: string
          p_amount: number
          p_reason?: string
        }
        Returns: number
      }
      admin_set_company_status: {
        Args: {
          p_company_id: string
          p_status: CompanyStatus
        }
        Returns: Database['public']['Tables']['companies']['Row']
      }
      get_platform_command_center: {
        Args: Record<string, never>
        Returns: Json
      }
      get_platform_live_snapshot: {
        Args: Record<string, never>
        Returns: Json
      }
      get_platform_network_metrics: {
        Args: { p_days?: number }
        Returns: Json
      }
      get_platform_trial_funnel: {
        Args: Record<string, never>
        Returns: Json
      }
      list_admin_companies_page: {
        Args: {
          p_search?: string | null
          p_business_type?: string | null
          p_status?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      get_company_admin_360: {
        Args: { p_company_id: string }
        Returns: Json
      }
      get_company_health_score: {
        Args: { p_company_id: string }
        Returns: Json
      }
      list_admin_deliveries_page: {
        Args: {
          p_tracking_code?: string | null
          p_company_id?: string | null
          p_status?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      get_admin_delivery_detail: {
        Args: { p_delivery_id: string }
        Returns: Json
      }
      list_admin_map_points: {
        Args: { p_company_id?: string | null; p_status?: string | null }
        Returns: Json
      }
      get_admin_communications_summary: {
        Args: { p_days?: number }
        Returns: Json
      }
      list_admin_api_keys_page: {
        Args: {
          p_company_id?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      admin_global_search: {
        Args: { p_query: string; p_limit?: number }
        Returns: Json
      }
      admin_support_lookup: {
        Args: { p_query: string }
        Returns: Json
      }
      get_platform_alerts: {
        Args: Record<string, never>
        Returns: Json
      }
      list_audit_logs_admin: {
        Args: {
          p_company_id?: string | null
          p_action?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      admin_list_platform_users: {
        Args: {
          p_search?: string | null
          p_status?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      admin_platform_user_funnel: {
        Args: Record<string, never>
        Returns: Json
      }
      get_platform_analytics: {
        Args: Record<string, never>
        Returns: Json
      }
      get_company_usage: {
        Args: { p_company_id: string }
        Returns: Json
      }
      get_platform_billing_metrics: {
        Args: Record<string, never>
        Returns: Json
      }
      list_plans_admin: {
        Args: Record<string, never>
        Returns: Json
      }
      admin_upsert_plan: {
        Args: { p_payload: Json }
        Returns: Database['public']['Tables']['subscriptions']['Row']
      }
      admin_set_company_subscription: {
        Args: {
          p_company_id: string
          p_plan_id: string
          p_status: CompanySubscriptionStatus
          p_period_end?: string | null
        }
        Returns: Database['public']['Tables']['company_subscriptions']['Row']
      }
      admin_create_invoice: {
        Args: {
          p_company_id: string
          p_plan_id: string
          p_amount_cents: number
          p_period_start: string
          p_period_end: string
          p_due_at: string
        }
        Returns: Database['public']['Tables']['invoices']['Row']
      }
      admin_record_billing_payment: {
        Args: {
          p_company_id: string
          p_invoice_id: string
          p_amount_cents: number
          p_payment_method: BillingPaymentMethod
          p_reference?: string | null
          p_paid_at?: string | null
        }
        Returns: Database['public']['Tables']['subscription_billing_payments']['Row']
      }
      admin_mark_invoice_paid: {
        Args: {
          p_invoice_id: string
          p_payment_reference?: string | null
        }
        Returns: Database['public']['Tables']['invoices']['Row']
      }
      list_invoices_page: {
        Args: {
          p_company_id?: string | null
          p_status?: string | null
          p_search?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      list_billing_payments_page: {
        Args: {
          p_company_id?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      list_audit_logs_page: {
        Args: {
          p_company_id?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      can_use_feature: {
        Args: { p_company_id: string; p_feature_key: string }
        Returns: boolean
      }
      record_rider_location: {
        Args: {
          p_latitude: number
          p_longitude: number
          p_accuracy?: number | null
          p_heading?: number | null
          p_speed?: number | null
          p_tracking_state?: string
          p_delivery_id?: string | null
        }
        Returns: Json
      }
      list_company_rider_locations: {
        Args: { p_company_id: string }
        Returns: Json
      }
      get_public_delivery_tracking: {
        Args: { p_tracking_code: string; p_client_key?: string | null }
        Returns: Json
      }
      list_delivery_zones: { Args: { p_company_id: string }; Returns: Json }
      upsert_delivery_zone: { Args: { p_payload: Json }; Returns: Json }
      get_operational_analytics: {
        Args: { p_company_id: string; p_days?: number }
        Returns: Json
      }
      get_rider_performance_metrics: {
        Args: { p_company_id: string; p_days?: number }
        Returns: Json
      }
      create_company_api_key: {
        Args: {
          p_company_id: string
          p_name: string
          p_permissions: Json
          p_expires_at?: string | null
        }
        Returns: Json
      }
      list_company_api_keys: { Args: { p_company_id: string }; Returns: Json }
      revoke_company_api_key: { Args: { p_key_id: string }; Returns: undefined }
      upsert_webhook_endpoint: { Args: { p_payload: Json }; Returns: Json }
      list_company_branches: { Args: { p_company_id: string }; Returns: Json }
      upsert_company_branch: { Args: { p_payload: Json }; Returns: Json }
      upsert_store_profile: { Args: { p_payload: Json }; Returns: Json }
      submit_store_profile_for_review: { Args: { p_company_id: string }; Returns: Json }
      upsert_product_category: { Args: { p_payload: Json }; Returns: Json }
      upsert_product: { Args: { p_payload: Json }; Returns: Json }
      upsert_product_option_group: { Args: { p_payload: Json }; Returns: Json }
      upsert_product_option: { Args: { p_payload: Json }; Returns: Json }
      upsert_product_image: { Args: { p_payload: Json }; Returns: Json }
      delete_product_image: { Args: { p_image_id: string }; Returns: undefined }
      adjust_product_stock: {
        Args: { p_product_id: string; p_delta: number; p_reason?: string }
        Returns: Json
      }
      get_or_create_cart: { Args: { p_vendor_company_id: string }; Returns: Json }
      add_cart_item: {
        Args: { p_cart_id: string; p_product_id: string; p_quantity: number; p_selected_options?: Json }
        Returns: Json
      }
      update_cart_item_quantity: { Args: { p_cart_item_id: string; p_quantity: number }; Returns: Json }
      remove_cart_item: { Args: { p_cart_item_id: string }; Returns: undefined }
      get_public_store_catalog: { Args: { p_slug: string }; Returns: Json }
      get_cart_summary: { Args: { p_cart_id: string }; Returns: Json }
      submit_commerce_order: {
        Args: {
          p_cart_id: string
          p_customer_name: string
          p_delivery_address?: string | null
          p_delivery_area_summary?: string | null
          p_delivery_latitude?: number | null
          p_delivery_longitude?: number | null
          p_delivery_instructions?: string | null
          p_payment_method?: string
        }
        Returns: Json
      }
      vendor_accept_commerce_order: { Args: { p_order_id: string }; Returns: Json }
      vendor_reject_commerce_order: { Args: { p_order_id: string; p_reason?: string }; Returns: Json }
      vendor_mark_order_preparing: { Args: { p_order_id: string }; Returns: Json }
      vendor_mark_order_ready: { Args: { p_order_id: string }; Returns: Json }
      list_vendor_commerce_orders_page: {
        Args: { p_vendor_company_id: string; p_fulfillment_statuses?: string[] | null; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      get_vendor_commerce_overview: { Args: { p_vendor_company_id: string }; Returns: Json }
      admin_set_vendor_state: {
        Args: { p_company_id: string; p_state: string; p_reason?: string | null }
        Returns: Json
      }
      admin_list_vendor_stores: {
        Args: { p_status?: string | null; p_search?: string | null; p_limit?: number; p_offset?: number }
        Returns: Json
      }
      list_vehicles_page: {
        Args: {
          p_company_id: string
          p_search?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      upsert_vehicle: { Args: { p_payload: Json }; Returns: Json }
      assign_rider_vehicle: {
        Args: { p_rider_id: string; p_vehicle_id: string }
        Returns: Json
      }
      record_vehicle_maintenance: { Args: { p_payload: Json }; Returns: Json }
      upsert_warehouse: { Args: { p_payload: Json }; Returns: Json }
      upsert_inventory_item: { Args: { p_payload: Json }; Returns: Json }
      inventory_receive_stock: {
        Args: {
          p_warehouse_id: string
          p_item_id: string
          p_quantity: number
          p_notes?: string | null
        }
        Returns: Json
      }
      inventory_adjust_stock: {
        Args: {
          p_warehouse_id: string
          p_item_id: string
          p_quantity_delta: number
          p_notes?: string | null
        }
        Returns: Json
      }
      create_cash_settlement: { Args: { p_rider_id: string }; Returns: Json }
      submit_cash_settlement: {
        Args: { p_settlement_id: string; p_received_cents: number }
        Returns: Json
      }
      reconcile_cash_settlement: { Args: { p_settlement_id: string }; Returns: Json }
      get_profitability_report: {
        Args: { p_company_id: string; p_branch_id?: string | null; p_days?: number }
        Returns: Json
      }
      request_delivery_return: {
        Args: { p_delivery_id: string; p_reason: string }
        Returns: Json
      }
      advance_delivery_return: { Args: { p_return_id: string; p_status: string }; Returns: Json }
      queue_outbound_sms: {
        Args: {
          p_company_id: string
          p_phone: string
          p_body: string
          p_delivery_id?: string | null
        }
        Returns: boolean
      }
      create_delivery_request: { Args: { p_payload: Json }; Returns: Json }
      publish_delivery_request: {
        Args: { p_request_id: string; p_merchant_company_id: string }
        Returns: Json
      }
      cancel_delivery_request: {
        Args: {
          p_request_id: string
          p_merchant_company_id: string
          p_reason?: string | null
        }
        Returns: Json
      }
      list_delivery_requests_page: {
        Args: {
          p_merchant_company_id: string
          p_status?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      list_marketplace_jobs_page: {
        Args: {
          p_provider_company_id: string
          p_status?: string | null
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      accept_marketplace_offer: {
        Args: { p_offer_id: string; p_provider_company_id: string }
        Returns: Json
      }
      request_commerce_order_delivery: { Args: { p_order_id: string }; Returns: Json }
      select_commerce_delivery_offer: { Args: { p_order_id: string; p_offer_id: string }; Returns: Json }
      get_commerce_order_delivery_status: { Args: { p_order_id: string }; Returns: Json }
      reject_marketplace_offer: {
        Args: { p_offer_id: string; p_provider_company_id: string }
        Returns: Json
      }
      list_marketplace_providers_page: {
        Args: {
          p_merchant_company_id: string
          p_limit?: number
          p_offset?: number
        }
        Returns: Json
      }
      upsert_provider_marketplace_profile: { Args: { p_payload: Json }; Returns: Json }
      upsert_merchant_provider_relationship: { Args: { p_payload: Json }; Returns: Json }
      get_marketplace_analytics: {
        Args: { p_company_id?: string | null; p_scope?: string }
        Returns: Json
      }
      create_provider_review: { Args: { p_payload: Json }; Returns: Json }
      admin_set_marketplace_suspension: {
        Args: {
          p_company_id: string
          p_suspended: boolean
          p_disable_provider?: boolean | null
        }
        Returns: null
      }
      get_company_onboarding_status: { Args: { p_company_id: string }; Returns: Json }
      get_platform_health_snapshot: { Args: Record<string, never>; Returns: Json }
      get_platform_security_snapshot: { Args: Record<string, never>; Returns: Json }
      admin_list_webhook_failures: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: Json
      }
      admin_retry_webhook_delivery: {
        Args: { p_delivery_id: string }
        Returns: Json
      }
      run_scheduled_maintenance_jobs: { Args: Record<string, never>; Returns: Json }
    }
    Enums: {
      company_status: CompanyStatus
      company_role: CompanyRole
      delivery_status: DeliveryStatus
      payment_status: PaymentStatus
      rider_status: RiderStatus
      company_subscription_status: CompanySubscriptionStatus
      invoice_status: InvoiceStatus
      billing_payment_method: BillingPaymentMethod
    }
    CompositeTypes: Record<string, never>
  }
}

export type Tables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Row']

export type DeliveryRow = Tables<'deliveries'>
export type Profile = Tables<'profiles'>
export type Company = Tables<'companies'>
export type CompanyUser = Tables<'company_users'>
export type RiderRow = Tables<'riders'>
export type CustomerRow = Tables<'customers'>
export type PaymentRow = Tables<'payments'>

export type AuthContext = {
  profile: Profile | null
  memberships: (CompanyUser & {
    company: Pick<Company, 'id' | 'name' | 'slug' | 'status' | 'business_type'>
  })[]
  activeCompanyId: string | null
  activeRole: CompanyRole | 'super_admin' | null
}
