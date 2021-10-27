# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg-hugo" {
  name = var.resource_group_name
  #   name     = "myTFResourceGroup"
  location = "East Us"

  #    tags = {
  #      Environment = "Terraform Getting Started"
  #      Team        = "DevOps"
  #    }
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet-hugo" {
  name                = "myTFVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-hugo.location
  resource_group_name = azurerm_resource_group.rg-hugo.name
}

resource "azurerm_subnet" "sub-hugo" {
  name                 = "sub-hugo"
  resource_group_name  = azurerm_resource_group.rg-hugo.name
  virtual_network_name = azurerm_virtual_network.vnet-hugo.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-hugo" {
  name                = "ip-hugo"
  resource_group_name = azurerm_resource_group.rg-hugo.name
  location            = azurerm_resource_group.rg-hugo.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }

}

# Criamos ele para poder pegar o ip publico no resource null_resource
  data "azurerm_public_ip" "data-ip-hugo"{
      resource_group_name = azurerm_resource_group.rg-hugo.name
      name = azurerm_public_ip.ip-hugo.name
  }

# firewall
resource "azurerm_network_security_group" "nsg-hugo" {
  name                = "nsg-hugo"
  location            = azurerm_resource_group.rg-hugo.location
  resource_group_name = azurerm_resource_group.rg-hugo.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

 security_rule {
    name                       = "mySql"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  
 security_rule {
    name                       = "apache"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = {
    environment = "Production"
  }
}

resource "azurerm_network_interface" "ni-hugo" {
  name                = "ni-hugo"
  location            = azurerm_resource_group.rg-hugo.location
  resource_group_name = azurerm_resource_group.rg-hugo.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-hugo.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-hugo.id
  }
}


resource "azurerm_network_interface_security_group_association" "nisga-hugo" {
  network_interface_id      = azurerm_network_interface.ni-hugo.id
  network_security_group_id = azurerm_network_security_group.nsg-hugo.id
}

resource "azurerm_virtual_machine" "vm-hugo" {
  name                  = "vm-hugo"
  location              = azurerm_resource_group.rg-hugo.location
  resource_group_name   = azurerm_resource_group.rg-hugo.name
  network_interface_ids = [azurerm_network_interface.ni-hugo.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "dsk-hugo"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "vm-hugo"
    admin_username = var.vm_user
    admin_password = var.vm_pass
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = "staging"
  }
}

# depois de carregada a maquina vamos conectar nela e executar alguma ação
resource "time_sleep" "esperar_30_segundos" {
  depends_on = [
    azurerm_virtual_machine.vm-hugo
  ]
  create_duration = "30s"

}

resource "null_resource" "install_" {
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.vm_user
      password = var.vm_pass
      host = data.azurerm_public_ip.data-ip-hugo.ip_address
    }
    inline = [
      "sudo apt update",
      "sudo apt-get install -y mysql-server-5.7"
    ]
  }

  depends_on = [
    time_sleep.esperar_30_segundos
  ]
}
