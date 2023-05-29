(* Automatically generated from gui_glade3.xml by lablgladecc, then *modified* *)

(* Global reference: *)
let gui_glade3_xml =
  Filename.concat (Initialization.Path.marionnet_home_gui) "gui_glade3.xml"
;;

(* --- *)
class dialog_A_PROPOS ?translation_domain () =
 let builder = GBuilder.builder ?translation_domain () in
 (* Should be equals to `Initialization.Path.marionnet_home', e.g "/home/jean/.opam/4.13.1/share/marionnet": *)
 (* let () = Printf.kfprintf flush stderr "HERE: gui.ml: cwd: %s\n" (Sys.getcwd ()) in *)
 let _ = builder#add_objects_from_file gui_glade3_xml ["dialog_A_PROPOS"] in
  object
    val toplevel = new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_A_PROPOS"))
    method toplevel = toplevel
   (* --- *)
    val dialog_A_PROPOS = new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_A_PROPOS"))
    method dialog_A_PROPOS = dialog_A_PROPOS
   (* --- *)
    val dialog_vbox2 = new GPack.box (GtkPack.Box.cast (builder#get_object "dialog-vbox2"))
    method dialog_vbox2 = dialog_vbox2
   (* --- *)
    val dialog_action_area2 = new GPack.button_box (GtkPack.BBox.cast (builder#get_object "dialog-action_area2"))
    method dialog_action_area2 = dialog_action_area2
   (* --- *)
    val closebutton_A_PROPOS = new GButton.button (GtkButton.Button.cast (builder#get_object "closebutton_A_PROPOS"))
    method closebutton_A_PROPOS = closebutton_A_PROPOS
   (* --- *)
    val vbox10 = new GPack.box (GtkPack.Box.cast (builder#get_object "vbox10"))
    method vbox10 = vbox10
   (* --- *)
    val label_dialog_A_PROPOS_title = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_title"))
    method label_dialog_A_PROPOS_title = label_dialog_A_PROPOS_title
   (* --- *)
    val hbox50 = new GPack.box (GtkPack.Box.cast (builder#get_object "hbox50"))
    method hbox50 = hbox50
   (* --- *)
    val scrolledwindow11 = new GBin.scrolled_window (GtkBin.ScrolledWindow.cast (builder#get_object "scrolledwindow11"))
    method scrolledwindow11 = scrolledwindow11
   (* --- *)
    val viewport10 = new GBin.viewport (GtkBin.Viewport.cast (builder#get_object "viewport10"))
    method viewport10 = viewport10
   (* --- *)
    val image366 = new GMisc.image (GtkMisc.Image.cast (builder#get_object "image366"))
    method image366 = image366
   (* --- *)
    val notebook_dialog_A_PROPOS = new GPack.notebook (GtkPack.Notebook.cast (builder#get_object "notebook_dialog_A_PROPOS"))
    method notebook_dialog_A_PROPOS = notebook_dialog_A_PROPOS
   (* --- *)
    val label_dialog_A_PROPOS_a_propos_content = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_a_propos_content"))
    method label_dialog_A_PROPOS_a_propos_content = label_dialog_A_PROPOS_a_propos_content
   (* --- *)
    val label_dialog_A_PROPOS_a_propos = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_a_propos"))
    method label_dialog_A_PROPOS_a_propos = label_dialog_A_PROPOS_a_propos
   (* --- *)
    val label_dialog_A_PROPOS_authors_content = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_authors_content"))
    method label_dialog_A_PROPOS_authors_content = label_dialog_A_PROPOS_authors_content
   (* --- *)
    val label_dialog_A_PROPOS_authors = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_authors"))
    method label_dialog_A_PROPOS_authors = label_dialog_A_PROPOS_authors
   (* --- *)
    val label_dialog_A_PROPOS_license_content = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_license_content"))
    method label_dialog_A_PROPOS_license_content = label_dialog_A_PROPOS_license_content
   (* --- *)
    val label_dialog_A_PROPOS_license = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_license"))
    method label_dialog_A_PROPOS_license = label_dialog_A_PROPOS_license
   (* --- *)
    val vbox8 = new GPack.box (GtkPack.Box.cast (builder#get_object "vbox8"))
    method vbox8 = vbox8
   (* --- *)
    val label_dialog_A_PROPOS_thanks_content = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_thanks_content"))
    method label_dialog_A_PROPOS_thanks_content = label_dialog_A_PROPOS_thanks_content
   (* --- *)
    val hbox2 = new GPack.box (GtkPack.Box.cast (builder#get_object "hbox2"))
    method hbox2 = hbox2
   (* --- *)
    val label_dialog_A_PROPOS_thanks_sponsors = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_thanks_sponsors"))
    method label_dialog_A_PROPOS_thanks_sponsors = label_dialog_A_PROPOS_thanks_sponsors
   (* --- *)
    val image23 = new GMisc.image (GtkMisc.Image.cast (builder#get_object "image23"))
    method image23 = image23
   (* --- *)
    val label_dialog_A_PROPOS_thanks = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_dialog_A_PROPOS_thanks"))
    method label_dialog_A_PROPOS_thanks = label_dialog_A_PROPOS_thanks
   (* --- *)
    method reparent parent =
      dialog_vbox2#misc#reparent parent;
      toplevel#destroy ()
  end

class dialog_MESSAGE ?translation_domain () =
 let builder = GBuilder.builder ?translation_domain () in
  let _ = builder#add_objects_from_file gui_glade3_xml ["dialog_MESSAGE"] in

  object
    val toplevel =
      new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_MESSAGE"))
    method toplevel = toplevel
    val dialog_MESSAGE =
      new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_MESSAGE"))
    method dialog_MESSAGE = dialog_MESSAGE
    val dialog_vbox3 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "dialog-vbox3"))
    method dialog_vbox3 = dialog_vbox3
    val dialog_action_area3 =
      new GPack.button_box (GtkPack.BBox.cast (builder#get_object "dialog-action_area3"))
    method dialog_action_area3 = dialog_action_area3
    val closebutton_MESSAGE =
      new GButton.button (GtkButton.Button.cast (builder#get_object "closebutton_MESSAGE"))
    method closebutton_MESSAGE = closebutton_MESSAGE
    val vbox11 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox11"))
    method vbox11 = vbox11
    val hbox51 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox51"))
    method hbox51 = hbox51
    val image =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image"))
    method image = image
    val title =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "title"))
    method title = title
    val content =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "content"))
    method content = content
    method reparent parent =
      dialog_vbox3#misc#reparent parent;
      toplevel#destroy ()
  end

class dialog_QUESTION ?translation_domain () =
 let builder = GBuilder.builder ?translation_domain () in
 let _ = builder#add_objects_from_file gui_glade3_xml ["dialog_QUESTION"] in
  object
    val toplevel =
      new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_QUESTION"))
    method toplevel = toplevel
    val dialog_QUESTION =
      new GWindow.dialog_any (GtkWindow.Dialog.cast (builder#get_object "dialog_QUESTION"))
    method dialog_QUESTION = dialog_QUESTION
    val vbox12 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox12"))
    method vbox12 = vbox12
    val hbuttonbox3 =
      new GPack.button_box (GtkPack.BBox.cast (builder#get_object "hbuttonbox3"))
    method hbuttonbox3 = hbuttonbox3
    val nobutton =
      new GButton.button (GtkButton.Button.cast (builder#get_object "nobutton"))
    method nobutton = nobutton
    val yesbutton =
      new GButton.button (GtkButton.Button.cast (builder#get_object "yesbutton"))
    method yesbutton = yesbutton
    val vbox13 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox13"))
    method vbox13 = vbox13
    val hbox52 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox52"))
    method hbox52 = hbox52
    val image399 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image399"))
    method image399 = image399
    val title_QUESTION =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "title_QUESTION"))
    method title_QUESTION = title_QUESTION
    method reparent parent =
      vbox12#misc#reparent parent;
      toplevel#destroy ()
  end
class window_MARIONNET ?translation_domain () =
 let builder = GBuilder.builder ?translation_domain () in
 let _ = builder#add_objects_from_file gui_glade3_xml ["window_MARIONNET"] in
  object
    val toplevel =
      new GWindow.window (GtkWindow.Window.cast (builder#get_object "window_MARIONNET"))
    method toplevel = toplevel
    val window_MARIONNET =
      new GWindow.window (GtkWindow.Window.cast (builder#get_object "window_MARIONNET"))
    method window_MARIONNET = window_MARIONNET
    val vbox1 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox1"))
    method vbox1 = vbox1
    val menubar_MARIONNET =
      new GMenu.menu_shell (GtkMenu.MenuBar.cast (builder#get_object "menubar_MARIONNET"))
    method menubar_MARIONNET = menubar_MARIONNET
    val notebook_CENTRAL =
      new GPack.notebook (GtkPack.Notebook.cast (builder#get_object "notebook_CENTRAL"))
    method notebook_CENTRAL = notebook_CENTRAL
    val hbox1 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox1"))
    method hbox1 = hbox1
    val scrolledwindow2 =
      new GBin.scrolled_window (GtkBin.ScrolledWindow.cast (builder#get_object "scrolledwindow2"))
    method scrolledwindow2 = scrolledwindow2
    val viewport2 =
      new GBin.viewport (GtkBin.Viewport.cast (builder#get_object "viewport2"))
    method viewport2 = viewport2
    val hbox_COMPONENTS =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox_COMPONENTS"))
    method hbox_COMPONENTS = hbox_COMPONENTS
    val toolbar_COMPONENTS =
      new GButton.toolbar (GtkButton.Toolbar.cast (builder#get_object "toolbar_COMPONENTS"))
    method toolbar_COMPONENTS = toolbar_COMPONENTS
    val vseparator1 =
      new GObj.widget_full (GtkMisc.Separator.cast (builder#get_object "vseparator1"))
    method vseparator1 = vseparator1
    val vbox3 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox3"))
    method vbox3 = vbox3
    val label_VIRTUAL_NETWORK =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_VIRTUAL_NETWORK"))
    method label_VIRTUAL_NETWORK = label_VIRTUAL_NETWORK
    val notebook_INTERNAL =
      new GPack.notebook (GtkPack.Notebook.cast (builder#get_object "notebook_INTERNAL"))
    method notebook_INTERNAL = notebook_INTERNAL
    val hbox31 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox31"))
    method hbox31 = hbox31
    val scrolledwindow1 =
      new GBin.scrolled_window (GtkBin.ScrolledWindow.cast (builder#get_object "scrolledwindow1"))
    method scrolledwindow1 = scrolledwindow1
    val viewport1 =
      new GBin.viewport (GtkBin.Viewport.cast (builder#get_object "viewport1"))
    method viewport1 = viewport1
    val sketch =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "sketch"))
    method sketch = sketch
    val toolbar_DOT_TUNING =
      new GButton.toolbar (GtkButton.Toolbar.cast (builder#get_object "toolbar_DOT_TUNING"))
    method toolbar_DOT_TUNING = toolbar_DOT_TUNING
    val toolitem65 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem65"))
    method toolitem65 = toolitem65
    val label_DOT_TUNING_NODES =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DOT_TUNING_NODES"))
    method label_DOT_TUNING_NODES = label_DOT_TUNING_NODES
    val toolitem254 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem254"))
    method toolitem254 = toolitem254
    val vscale_DOT_TUNING_ICONSIZE =
      new GRange.scale (GtkRange.Scale.cast (builder#get_object "vscale_DOT_TUNING_ICONSIZE"))
    method vscale_DOT_TUNING_ICONSIZE = vscale_DOT_TUNING_ICONSIZE
    val toolitem67 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem67"))
    method toolitem67 = toolitem67
    val button_DOT_TUNING_SHUFFLE =
      new GButton.button (GtkButton.Button.cast (builder#get_object "button_DOT_TUNING_SHUFFLE"))
    method button_DOT_TUNING_SHUFFLE = button_DOT_TUNING_SHUFFLE
    val image450 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image450"))
    method image450 = image450
    val toolitem69 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem69"))
    method toolitem69 = toolitem69
    val button_DOT_TUNING_UNSHUFFLE =
      new GButton.button (GtkButton.Button.cast (builder#get_object "button_DOT_TUNING_UNSHUFFLE"))
    method button_DOT_TUNING_UNSHUFFLE = button_DOT_TUNING_UNSHUFFLE
    val image580 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image580"))
    method image580 = image580
    val toolitem68 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem68"))
    method toolitem68 = toolitem68
    val hseparator83 =
      new GObj.widget_full (GtkMisc.Separator.cast (builder#get_object "hseparator83"))
    method hseparator83 = hseparator83
    val toolitem651 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem651"))
    method toolitem651 = toolitem651
    val label_DOT_TUNING_EDGES =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DOT_TUNING_EDGES"))
    method label_DOT_TUNING_EDGES = label_DOT_TUNING_EDGES
    val toolitem244 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem244"))
    method toolitem244 = toolitem244
    val button_DOT_TUNING_RANKDIR_TB =
      new GButton.button (GtkButton.Button.cast (builder#get_object "button_DOT_TUNING_RANKDIR_TB"))
    method button_DOT_TUNING_RANKDIR_TB = button_DOT_TUNING_RANKDIR_TB
    val image670 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image670"))
    method image670 = image670
    val toolitem246 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem246"))
    method toolitem246 = toolitem246
    val button_DOT_TUNING_RANKDIR_LR =
      new GButton.button (GtkButton.Button.cast (builder#get_object "button_DOT_TUNING_RANKDIR_LR"))
    method button_DOT_TUNING_RANKDIR_LR = button_DOT_TUNING_RANKDIR_LR
    val image780 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image780"))
    method image780 = image780
    val toolitem247 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem247"))
    method toolitem247 = toolitem247
    val vscale_DOT_TUNING_NODESEP =
      new GRange.scale (GtkRange.Scale.cast (builder#get_object "vscale_DOT_TUNING_NODESEP"))
    method vscale_DOT_TUNING_NODESEP = vscale_DOT_TUNING_NODESEP
    val toolitem248 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem248"))
    method toolitem248 = toolitem248
    val menubar_DOT_TUNING_INVERT =
      new GMenu.menu_shell (GtkMenu.MenuBar.cast (builder#get_object "menubar_DOT_TUNING_INVERT"))
    method menubar_DOT_TUNING_INVERT = menubar_DOT_TUNING_INVERT
    val imagemenuitem_DOT_TUNING_INVERT =
      new GMenu.menu_item (GtkMenu.MenuItem.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT"))
    method imagemenuitem_DOT_TUNING_INVERT = imagemenuitem_DOT_TUNING_INVERT
    val imagemenuitem_DOT_TUNING_INVERT_menu =
      new GMenu.menu (GtkMenu.Menu.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT_menu"))
    method imagemenuitem_DOT_TUNING_INVERT_menu = imagemenuitem_DOT_TUNING_INVERT_menu
    val imagemenuitem_DOT_TUNING_INVERT_DIRECT =
      new GMenu.menu_item (GtkMenu.MenuItem.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT_DIRECT"))
    method imagemenuitem_DOT_TUNING_INVERT_DIRECT = imagemenuitem_DOT_TUNING_INVERT_DIRECT
    val imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu =
      new GMenu.menu (GtkMenu.Menu.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu"))
    method imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu = imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu
    val item127 =
      new GMenu.check_menu_item (GtkMenu.CheckMenuItem.cast (builder#get_object "item127"))
    method item127 = item127
    val imagemenuitem_DOT_TUNING_INVERT_CROSSOVER =
      new GMenu.menu_item (GtkMenu.MenuItem.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT_CROSSOVER"))
    method imagemenuitem_DOT_TUNING_INVERT_CROSSOVER = imagemenuitem_DOT_TUNING_INVERT_CROSSOVER
    val imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu =
      new GMenu.menu (GtkMenu.Menu.cast (builder#get_object "imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu"))
    method imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu = imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu
    val menuitem17 =
      new GMenu.check_menu_item (GtkMenu.CheckMenuItem.cast (builder#get_object "menuitem17"))
    method menuitem17 = menuitem17
    val toolitem251 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem251"))
    method toolitem251 = toolitem251
    val button_DOT_TUNING_CURVED_LINES =
      new GButton.button (GtkButton.Button.cast (builder#get_object "button_DOT_TUNING_CURVED_LINES"))
    method button_DOT_TUNING_CURVED_LINES = button_DOT_TUNING_CURVED_LINES
    val image671 =
      new GMisc.image (GtkMisc.Image.cast (builder#get_object "image671"))
    method image671 = image671
    val toolitem249 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem249"))
    method toolitem249 = toolitem249
    val hseparator84 =
      new GObj.widget_full (GtkMisc.Separator.cast (builder#get_object "hseparator84"))
    method hseparator84 = hseparator84
    val toolitem250 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem250"))
    method toolitem250 = toolitem250
    val label_DOT_TUNING_LABELS =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DOT_TUNING_LABELS"))
    method label_DOT_TUNING_LABELS = label_DOT_TUNING_LABELS
    val toolitem258 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem258"))
    method toolitem258 = toolitem258
    val vscale_DOT_TUNING_LABELDISTANCE =
      new GRange.scale (GtkRange.Scale.cast (builder#get_object "vscale_DOT_TUNING_LABELDISTANCE"))
    method vscale_DOT_TUNING_LABELDISTANCE = vscale_DOT_TUNING_LABELDISTANCE
    val toolitem261 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem261"))
    method toolitem261 = toolitem261
    val hseparator85 =
      new GObj.widget_full (GtkMisc.Separator.cast (builder#get_object "hseparator85"))
    method hseparator85 = hseparator85
    val toolitem255 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem255"))
    method toolitem255 = toolitem255
    val label_DOT_TUNING_AREA =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DOT_TUNING_AREA"))
    method label_DOT_TUNING_AREA = label_DOT_TUNING_AREA
    val toolitem269 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem269"))
    method toolitem269 = toolitem269
    val vscale_DOT_TUNING_EXTRASIZE =
      new GRange.scale (GtkRange.Scale.cast (builder#get_object "vscale_DOT_TUNING_EXTRASIZE"))
    method vscale_DOT_TUNING_EXTRASIZE = vscale_DOT_TUNING_EXTRASIZE
    val toolitem268 =
      new GButton.tool_item (GtkButton.ToolItem.cast (builder#get_object "toolitem268"))
    method toolitem268 = toolitem268
    val hseparator86 =
      new GObj.widget_full (GtkMisc.Separator.cast (builder#get_object "hseparator86"))
    method hseparator86 = hseparator86
    val label_IMAGE =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_IMAGE"))
    method label_IMAGE = label_IMAGE
    val ifconfig_viewport =
      new GPack.box (GtkPack.Box.cast (builder#get_object "ifconfig_viewport"))
    method ifconfig_viewport = ifconfig_viewport
    val label_INTERFACES =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_INTERFACES"))
    method label_INTERFACES = label_INTERFACES
    val defects_viewport =
      new GPack.box (GtkPack.Box.cast (builder#get_object "defects_viewport"))
    method defects_viewport = defects_viewport
    val label_DEFECT =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DEFECT"))
    method label_DEFECT = label_DEFECT
    val filesystem_history_viewport =
      new GPack.box (GtkPack.Box.cast (builder#get_object "filesystem_history_viewport"))
    method filesystem_history_viewport = filesystem_history_viewport
    val label_DISKS =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_DISKS"))
    method label_DISKS = label_DISKS
    val label_COMPONENTS =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_TAB_COMPONENTS"))
    method label_COMPONENTS = label_COMPONENTS
    val vbox555775 =
      new GPack.box (GtkPack.Box.cast (builder#get_object "vbox555775"))
    method vbox555775 = vbox555775
    val label_TAB_DOCUMENTS =
      new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_TAB_DOCUMENTS"))
    method label_TAB_DOCUMENTS = label_TAB_DOCUMENTS
    val documents_viewport =
      new GPack.box (GtkPack.Box.cast (builder#get_object "documents_viewport"))
    method documents_viewport = documents_viewport
    (*val label_ENONCE = new GMisc.label (GtkMisc.Label.cast (builder#get_object "label_ENONCE"))
    method label_ENONCE = label_ENONCE*)
    val hbox_BASE =
      new GPack.box (GtkPack.Box.cast (builder#get_object "hbox_BASE"))
    method hbox_BASE = hbox_BASE
    val statusbar =
      new GMisc.statusbar (GtkMisc.Statusbar.cast (builder#get_object "statusbar"))
    method statusbar = statusbar
    method reparent parent =
      vbox1#misc#reparent parent;
      toplevel#destroy ()
  end
