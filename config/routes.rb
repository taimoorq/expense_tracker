Rails.application.routes.draw do
  devise_for :admin_users, path: "admin", controllers: {
    sessions: "admin/sessions"
  }
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords"
  }
  resource :theme, only: :update
  resource :settings, only: [ :show, :update ]

  namespace :admin do
    root "dashboard#show"
    resources :users, only: [ :index, :show ] do
      member do
        patch :suspend
        patch :restore
      end
    end
  end

  root "overview#show"
  get "help", to: "help#show", as: :help
  patch "help/release_notes/acknowledge", to: "help#acknowledge_release_notes", as: :acknowledge_help_release_notes
  get "backup_restore", to: "backup_restores#show", as: :backup_restore
  get "backup_restore/sample", to: "backup_restores#sample", as: :sample_backup_restore
  post "backup_restore/export", to: "backup_restores#export", as: :export_backup_restore
  post "backup_restore/preview", to: "backup_restores#preview", as: :preview_backup_restore
  post "backup_restore/import", to: "backup_restores#import", as: :import_backup_restore
  get "planning_templates", to: "planning_templates#index", as: :planning_templates
  resources :accounts, except: [ :destroy ] do
    resources :account_snapshots, only: [ :create, :edit, :update, :destroy ]
  end

  resources :budget_months, only: [ :index, :show, :new, :create ] do
    post :generate_paychecks, on: :member
    post :generate_subscriptions, on: :member
    post :generate_monthly_bills, on: :member
    post :generate_payment_plans, on: :member
    post :estimate_credit_cards, on: :member
    resources :expense_entries, only: [ :create, :show, :edit, :update, :destroy ] do
      collection do
        get :new_wizard
      end

      member do
        get :edit_template
        patch :update_template
      end
    end
  end

  resources :pay_schedules, only: [ :create, :update, :destroy ]
  resources :subscriptions, only: [ :create, :update, :destroy ]
  resources :monthly_bills, only: [ :create, :update, :destroy ]
  resources :payment_plans, only: [ :create, :update, :destroy ]
  resources :credit_cards, only: [ :create, :update, :destroy ]

  post "imports/csv", to: "imports#create", as: :import_csv

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
