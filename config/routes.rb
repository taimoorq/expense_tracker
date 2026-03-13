Rails.application.routes.draw do
  devise_for :users
  root "budget_months#index"
  get "help", to: "help#show", as: :help
  get "planning_templates", to: "planning_templates#index", as: :planning_templates

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

  resources :pay_schedules, only: [ :create, :destroy ]
  resources :subscriptions, only: [ :create, :destroy ]
  resources :monthly_bills, only: [ :create, :destroy ]
  resources :payment_plans, only: [ :create, :destroy ]
  resources :credit_cards, only: [ :create, :destroy ]

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
