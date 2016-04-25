package gui.menu;

import gui.Lang;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.GridLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.File;

import javax.swing.ButtonGroup;
import javax.swing.JButton;
import javax.swing.JEditorPane;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JPanel;
import javax.swing.JRadioButton;
import javax.swing.JTextArea;

import com.sun.glass.events.KeyEvent;

public class PDDL4T_interface extends JFrame implements ActionListener {
	private JPanel j = new JPanel();
	private JRadioButton instButton = new JRadioButton("Actions totalement instanciees");
	private JRadioButton decButton = new JRadioButton("Actions decoupees selon leurs arguments");
	private ButtonGroup action = new ButtonGroup();
	private JRadioButton dirButton = new JRadioButton("Codage direct des actions");
	private JRadioButton planButton = new JRadioButton("Codage du graphe de planifications");
	private ButtonGroup graphe = new ButtonGroup();
	private JRadioButton pasButton = new JRadioButton("Pas � pas");
	private JRadioButton itButton = new JRadioButton("Iteratif");
	private ButtonGroup fonc = new ButtonGroup();
	
	private JButton chargerProbleme = new JButton("Charger le probleme");
	private JButton chargerDomaine = new JButton("Charger le domaine");
	private JButton valider = new JButton("Valider");
	private JButton annuler = new JButton("Annuler");
	
	private String problemeACharger = "Aucun";
	private JTextArea textProbleme = new JTextArea(problemeACharger);
	private String domaineACharger = "Aucun";
	private JTextArea textDomaine = new JTextArea(domaineACharger);
	
	
	public PDDL4T_interface() {
		this.setTitle("Options");
		this.setSize(300, 300);
		//ajouter un moyen de charger un chemin d'acc�s.

        instButton.setMnemonic(KeyEvent.VK_C); 
        instButton.setSelected(true);

        decButton.setMnemonic(KeyEvent.VK_V); 
        decButton.setSelected(false);
        
        dirButton.setMnemonic(KeyEvent.VK_B); 
        dirButton.setSelected(true);

        planButton.setMnemonic(KeyEvent.VK_N); 
        planButton.setSelected(false);
        
        pasButton.setMnemonic(KeyEvent.VK_P); 
        pasButton.setSelected(true);

        itButton.setMnemonic(KeyEvent.VK_I); 
        itButton.setSelected(false);

        //put the radiobutton in groupe  to get only one true radiobutton per groupe
        action.add(instButton);
        action.add(decButton);
        
        graphe.add(dirButton);
        graphe.add(planButton);
        
        fonc.add(pasButton);
        fonc.add(itButton);
        
        //add action listener to the different button
        chargerProbleme.addActionListener(new java.awt.event.ActionListener() {
            public void actionPerformed(java.awt.event.ActionEvent evt) {
            	chargerProblemeActionPerformed(evt);
            }
        });
        chargerDomaine.addActionListener(new java.awt.event.ActionListener() {
            public void actionPerformed(java.awt.event.ActionEvent evt) {
            	chargerDomaineActionPerformed(evt);
            }
        });
        
        
        instButton.addActionListener(new StateListener());
        decButton.addActionListener(new StateListener());
        dirButton.addActionListener(new StateListener());
        planButton.addActionListener(new StateListener());
        pasButton.addActionListener(new StateListener());
        itButton.addActionListener(new StateListener());
        valider.addActionListener(new java.awt.event.ActionListener() {
            public void actionPerformed(java.awt.event.ActionEvent evt) {
            	validerActionPerformed(evt);
            }
        });
        annuler.addActionListener(new java.awt.event.ActionListener() {
            public void actionPerformed(java.awt.event.ActionEvent evt) {
            	annulerActionPerformed(evt);
            }
        });
        
        //i'll add all the button to the interface, using BorderLayout and GridLayout to place them.
        j.setBackground(Color.white);
        j.setLayout(new BorderLayout());
        JPanel top = new JPanel(new GridLayout( 2, 2));
        top.add(chargerProbleme);
        top.add(textProbleme);
        top.add(chargerDomaine);
        top.add(textDomaine);
        JPanel mid = new JPanel(new GridLayout( 3, 2));
        mid.add(instButton);
        mid.add(decButton);
        mid.add(dirButton);
        mid.add(planButton);
        mid.add(pasButton);
        mid.add(itButton);  
        JPanel bot = new JPanel(new GridLayout( 1, 2));
        bot.add(valider);
        bot.add(annuler);
        j.add(top, BorderLayout.NORTH);
        j.add(mid, BorderLayout.CENTER); 
        j.add(bot, BorderLayout.SOUTH);
        
        //I put the frame in the center of the screen andvisible
        this.setLocationRelativeTo(null);
        this.setContentPane(j);
        this.setVisible(true); 
	}

	class StateListener implements ActionListener{
	    public void actionPerformed(ActionEvent e) {
	      System.out.println("source : " + ((JRadioButton)e.getSource()).getText() + " - etat : " + ((JRadioButton)e.getSource()).isSelected());
	    }
	  }
	
	private void chargerProblemeActionPerformed(java.awt.event.ActionEvent evt) {  
		JFileChooser chooser = new JFileChooser();
		int returnVal = chooser.showOpenDialog(null);
		if (returnVal == JFileChooser.APPROVE_OPTION) {
			File selection = chooser.getSelectedFile();
			problemeACharger =  selection.getAbsolutePath();
			textProbleme.setText(problemeACharger);
		}
	}
	private void chargerDomaineActionPerformed(java.awt.event.ActionEvent evt) {  
		JFileChooser chooser = new JFileChooser();
		int returnVal = chooser.showOpenDialog(null);
		if (returnVal == JFileChooser.APPROVE_OPTION) {
			File selection = chooser.getSelectedFile();
			domaineACharger =  selection.getAbsolutePath();
			textDomaine.setText(domaineACharger);
		}
	}
	
	public void validerActionPerformed(java.awt.event.ActionEvent e) {
		// En attendant d'�te racorder aux differents programmes de traitement.
		if(problemeACharger.compareTo("Aucun") == 0 || domaineACharger.compareTo("Aucun") == 0){
			JEditorPane jEditorPane = new JEditorPane();
	        jEditorPane.setEditable(false);
	        jEditorPane.setText("Vous devez charger un probleme ET un domaine.");
	        JFrame j = new JFrame();
	        j.getContentPane().add(jEditorPane, BorderLayout.CENTER);
	        j.setSize(new Dimension(300,70));
	        j.setLocationRelativeTo(null);
	        j.setVisible(true);
		}else{
			this.setVisible(false);	
			this.dispose();
		}
	}
	
	public void annulerActionPerformed(java.awt.event.ActionEvent e) {
			this.setVisible(false);	
			this.dispose();
	}

	@Override
	public void actionPerformed(ActionEvent e) {
		// TODO Auto-generated method stub
		
	}
}
    