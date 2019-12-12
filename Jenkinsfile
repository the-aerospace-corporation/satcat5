// Copyright 2019 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

pipeline {
    agent { label 'Vivado2015.4' }
    stages {
        stage ('Test') {
            steps {
                dir('.') {
                     sh './build_all.sh'
                }
                dir('./sim/vhdl/') {
                     sh './xsim_run.sh'
                     sh 'python xsim_parse.py'
                }
            }
        }
    }

    post {
        success {
            // junit has issues with paths, so soft-link it first
            sh 'ln -s sim/vhdl/sim_results.xml $WORKSPACE'
            junit 'sim_results.xml'

            // TODO - bundle these into a zip?
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_arty_a7_35t/switch_arty_a7_35t.runs/impl_1/switch_top_arty_a7_rmii.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_arty_a7_35t/switch_arty_a7_35t.runs/impl_1/*.rpt'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_arty_a7_100t/switch_arty_a7_100t.runs/impl_1/switch_top_arty_a7_rmii.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_arty_a7_100t/switch_arty_a7_100t.runs/impl_1/*.rpt'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_base/switch_proto_v1_base.runs/impl_1/switch_top_ac701_base.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_base/switch_proto_v1_base.runs/impl_1/*.rpt'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_rgmii/switch_proto_v1_rgmii.runs/impl_1/switch_top_ac701_rgmii.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_rgmii/switch_proto_v1_rgmii.runs/impl_1/*.rpt'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_sgmii/switch_proto_v1_sgmii.runs/impl_1/switch_top_ac701_sgmii.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v1_sgmii/switch_proto_v1_sgmii.runs/impl_1/*.rpt'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v2/switch_proto_v2.runs/impl_1/switch_top_proto_v2.bit'
            archiveArtifacts artifacts: 'project/vivado_2015.4/switch_proto_v2/switch_proto_v2.runs/impl_1/*.rpt'
            // Archive sim results
            archiveArtifacts artifacts: 'sim/vhdl/xsim_tmp/simulate_*.log'
        }
    }
}
